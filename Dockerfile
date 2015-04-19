FROM ruby:2.2.2-onbuild

# go-cron stuff.. taken from github/webwurst/docker-go-cron
RUN curl -L https://github.com/odise/go-cron/releases/download/v0.0.6/go-cron-linux.gz \
 | zcat > /usr/local/bin/go-cron \
   && chmod u+x /usr/local/bin/go-cron

