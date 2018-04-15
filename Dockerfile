FROM centos:7
MAINTAINER R. Amosa <ron@cloudbuilder.io>

RUN \ 
    yum -y update && yum -y install epel-release && \
    yum -y install openssl openssh-clients openssh-server && \
    yum -y install bind-utils net-utils ppp pptp curl wget git which less \
    vim expect ansible python-pip bash-completion net-tools zip unzip && \
    yum -y clean all && \ 
    touch /run/utmp && \
    echo "root:root" | chpasswd

RUN \
    useradd loginid && \
    mkdir ~loginid/.ssh && \
    echo "loginid:loginid" | chpasswd 

ADD ["bin/forticlientsslvpn.xz", "/usr/local/bin"]
COPY ["bin/forticlientvpn.sh", "/usr/bin"]

COPY ["keys", "/home/loginid/.ssh"]
COPY ["conf/ssh.config", "/home/loginid/.ssh/config"]
COPY ["conf/bash_aliases", "/home/loginid/.alias"]

RUN echo " . ~/.alias " >> /home/loginid/.bashrc

RUN chown -R loginid:loginid /home/loginid/.ssh 
RUN chmod -R 600 /home/loginid/.ssh/*
RUN chown loginid:loginid /home/loginid/.alias

RUN /usr/local/bin/forticlientsslvpn/64bit/helper/setup.linux.sh 

COPY ["entrypoint.sh", "/"] 

RUN chmod 755 /entrypoint.sh 
RUN chmod 755 /usr/bin/forticlientvpn.sh 

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
