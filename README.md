# Docker Work VPN Container

I needed a really simple enclosed and fully functional work environment that wasn't on my work laptop so I could do work on another station, without having to mess that environment up with work stuff. And it needed to set my work VPN up without my input.

So Docker was of course the logical choice.

## Pre-requisites

* Docker installed
* your work ssh-keys
* your office AD login details
* copy of Fortinet Linux ssl cli client (see below for link) packed in a .xz file

## Objectives

what did I want my work container to do?

* fire up and connect the work Fortinet VPN client with no user input.
* have my authorised ssh-keys set up for all work environments I needed to be able to access
* have my bash alises loaded (cos I like convenience)

## Dockerfile

I'm going to go through each block and try and explain what's happening. I'll have a link at the end with all the files in full so you can skip to that to see everything in its' entirety.

So, what's it doing?

- sets up base image and installs desired packages (add as needed).
- install PPP & PPTP packages are a must for VPN to work.
- sets up 'utmp' and 'root' user, sets password

```ruby
FROM centos:7

RUN \
    yum -y update && yum -y install epel-release && \
    yum -y install openssl openssh-clients openssh-server && \
    yum -y install bind-utils net-utils ppp pptp curl wget git which less \
    vim expect ansible python-pip bash-completion net-tools zip unzip && \
    yum -y clean all && \
    touch /run/utmp && \
    echo "root:root" | chpasswd
```

Next
- it creates a (work) user
- creates our .ssh directory and
- sets the user's passwd (loginid = your AD login at the office)

```ruby
RUN \
    useradd loginid && \
    mkdir ~loginid/.ssh && \
    echo "loginid:loginid" | chpasswd
```

Next it's adding our vpn client package, and copying the vpn runtime script.

When you add this (or any package for that matter of this type) .xz file, Docker will automagically unpack the contents in your destination directory (in this case /usr/local/bin):

```ruby
ADD ["bin/forticlientsslvpn.xz", "/usr/local/bin"]
COPY ["bin/forticlientvpn.sh", "/usr/bin"]
```

Then, copy ALL my keys and my ssh config file to $HOME/.ssh:

```ruby
COPY ["keys", "/home/loginid/.ssh"]
COPY ["conf/ssh.config", "/home/loginid/.ssh/config"]
```

Also copy my bash aliases to ~/.alias, and add a line to my ~/.bashrc so that it automagically sources my aliases everytime I login

```ruby
COPY ["conf/bash_aliases", "/home/loginid/.alias"]
RUN echo " . ~/.alias " >> /home/loginid/.bashrc
```

set the right owners and permissions or my keys wont work

```ruby
RUN chown -R loginid:loginid /home/loginid/.ssh
RUN chmod -R 600 /home/loginid/.ssh/*
RUN chown loginid:loginid /home/loginid/.alias
```

Next, this script is needed by forticlient to inialise and accept the license:

```ruby
RUN /usr/local/bin/forticlientsslvpn/64bit/helper/setup.linux.sh
```

- copy our entrypoint.sh (see further down for setting this script up)
- and chmod 755 entrypoint and forticlientvpn** scripts:

```ruby
COPY ["entrypoint.sh", "/"]
RUN chmod 755 /entrypoint.sh
RUN chmod 755 /usr/bin/forticlientvpn.sh
```

That's it.

Next, we have to prep the forticlient setup so that it doesn't have to wait for us to input anything and it just goes ahead and

1. installs without us needing to accept the license
2. runs without us needing to type 'Y' to start the VPN tunnel

## Setting up the forticlient SSL VPN

When you first download the forticlient package on Linux and run it, you'll get an error saying you need to run the following script:

`/usr/local/bin/forticlientsslvpn/64bit/helper/setup.linux.sh`

and this will show you the license you have to scroll through and accept the license.

This is a problem if you just want the container to fire up, set itself up and run without any user input. So we need to remove this section of the script before we can run the container successfully

### Remove Section from 'setup.linux.sh'

This section is the one where you need to scroll through the 'more' output to the bottom, and say 'yes' or whatever to get it to go to the next step. We don't want to do this, we want things to work automagically.

So, remove this section from the script:

```ruby
...

if [ "$1" != "2" ]; then
        echo "begin setup at $base..." >> "$inlog"
        more "$base/License.txt"
        echo -n "Do you agree with this license ?[Yes/No]"
        read ans
        yn=`echo $ans|sed '
        s/y/Y/
        s/e/E/
        s/s/S/
        '`
        if [ "$yn" != "YES" -a "$yn" != "Y" ]; then
                touch "$base/.nolicense"
                chmod a+w "$base/.nolicense"
                echo "Do not agree with this license, aborting..."
                exit 0
        fi
fi
...
```
Just delete everything in this 'if' statement. Save your file. It's done.

### forticlient expect script
For the 2nd part, every time you fire up forticlient vpn it asks you if you want to start the VPN tunnel. Yes. Yes you do. and No, no you don't want to have to type 'Y' every time.

So, we want our entrypoint for the container to be an 'expect' bash script that answers that question for us. Big thanks and full credit for script goes to [mgeeky/github.com](https://gist.github.com/mgeeky/8afc0e32b8b97fd6f96fce6098615a93).

Just include your own VPN details and save this as 'entrypoint.sh'

```ruby
#!/usr/bin/env bash

FORTICLIENT_PATH="/usr/local/bin/forticlientsslvpn/64bit/forticlientsslvpn_cli"
VPN_HOST="host:port"
VPN_USER=""
VPN_PASS=""
```

Right, time to build our image.

## Build Work VPN Container Image

(make sure you're in the same folder as your Dockerfile file)

```ruby
$ docker build --rm -t companyname/vpn:centos7 .
```

## Run it!

Run the container, then 'exec' into it and you should find it connects to your work VPN and is ready for you to remote to all your work environments (well, mine anyway).

_note: you need to run container as 'privileged' for pppd kernel support
the vpn inside docker would complain about kernel not supporting pppd if you don't run privileged._

```ruby
$ docker run -dP --name=workvpn --privileged companyname/vpn:centos7
$ docker exec -u loginid -ti <name_of_container> /bin/bash
```


## Example of output success

Run `$ docker logs <name_of_container>` and see if you can see the following

```ruby
cloudbuilder@hx0:~/vpn $ docker logs workvpn
Killing previous instances of Forticlient SSL VPN client...
spawn /usr/local/bin/forticlientsslvpn/64bit/forticlientsslvpn_cli --server remote.site.com:443 --vpnuser loginid --keepalive
Password for VPN:
STATUS::Setting up the tunnel
STATUS::Connecting...
Certificate:Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number:


...
... //certificate output
... //certificate output
... //certificate output
...

The certificate for the SSLVPN server is invalid.
You are connecting to an untrusted server. which could put your confidential information at risk.
Would you like to connect to this server? (Y/N)
Y
STATUS::Login succeed
STATUS::Starting PPPd
STATUS::Initializing tunnel
STATUS::Connecting to server
STATUS::Connected
Press Ctrl-C to quit
STATUS::Tunnel running
```

When you see 'Tunnel running' you should be good to go!


