FROM phusion/passenger-customizable:1.0.5

# Copy services
COPY server_infra/docker/base/build/service /etc/service

# Add nginx config and prep to run as a service
COPY server_infra/docker/base/build/conf/nginx/nginx.conf /etc/nginx/sites-available/nginx.conf
RUN ln -s /etc/nginx/sites-available/nginx.conf /etc/nginx/sites-enabled/nginx.conf && \
  rm /etc/nginx/sites-enabled/default && \
  rm -f /etc/service/nginx/down

WORKDIR /home/app/greeter_server

COPY . .

RUN gem install bundler
RUN bundle config --global silence_root_warning 1
RUN bundle install

# LEAVE THIS COMMAND: it is used to start our monitoring/logging agents
CMD ["/sbin/my_init"]
