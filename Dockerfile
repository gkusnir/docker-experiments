FROM busybox:latest

WORKDIR /

VOLUME testvol1

COPY somefile.txt /testvol1/somefile.txt

