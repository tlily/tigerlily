@ECHO OFF
SET TERM=pcansi
SET CYGWIN=tty notitle binmode
set PATH=C:\tigerlily\bin;%PATH%
C:
cd \tigerlily\bin
perl tlily.plx %*
