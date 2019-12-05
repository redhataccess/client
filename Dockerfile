FROM node:carbon

#RUN addgroup -S hypothesis && adduser -S -G hypothesis -h /usr/src/app hypothesis
WORKDIR /usr/src/app

ARG NODE_ENV
ARG SIDEBAR_APP_URL
ARG CLIENT_URL
ARG ASSET_URL

COPY package.json .

# Ensure directories writeable by unprivileged user.
#RUN chown -R hypothesis:hypothesis *

# Fetch root cert
RUN curl https://password.corp.redhat.com/RH-IT-Root-CA.crt --output /usr/local/share/ca-certificates/RH-IT-Root-CA.crt \
 & update-ca-certificates \
 & yarn config set cafile /etc/ssl/certs/ca-certificates.crt

# Install dependencies.
#RUN NODE_ENV=production node --max_semi_space_size=1 --max_old_space_size=198 --optimize_for_size \
RUN node --max_semi_space_size=1 --max_old_space_size=198 --optimize_for_size `which npm` install

RUN npm install -g gulp-cli

# Copy the source files.
COPY . .
RUN make

#USER hypothesis

CMD ["gulp", "build", "serve-package"]
