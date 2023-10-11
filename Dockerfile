FROM kong:2.5.2

# Install luarocks
USER root 
RUN apk add --update luarocks

# Copy plugin rockspec and install
COPY jwt-validate-0.1.0-1.rockspec /tmp/
RUN luarocks install /tmp/jwt-validate-0.1.0-1.rockspec

# Enable plugin
RUN echo "custom_plugins = jwt-validate" >> /etc/kong/kong.conf 

USER kong