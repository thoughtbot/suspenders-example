FROM ruby:2.6.3-slim AS compile

ENV LANG en_US.UTF-8

RUN apt-get update -qq \
  && apt-get install -y \
  build-essential \
  git \
  libpq-dev \
  curl \
  && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | \
  apt-key add - \
  && echo "deb https://dl.yarnpkg.com/debian/ stable main" > \
  /etc/apt/sources.list.d/yarn.list \
  && apt-get update -qq \
  && apt-get install -y yarn \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir /app
WORKDIR /app

COPY Gemfile* /app/
RUN bundle config --global frozen 1 \
 && bundle install --without "development test" -j4 --retry 3 \
 && rm -rf /usr/local/bundle/cache/*.gem \
 && find /usr/local/bundle/gems/ -name "*.c" -delete \
 && find /usr/local/bundle/gems/ -name "*.o" -delete

COPY package.json yarn.lock /app/
RUN yarn install

COPY . /app

# The SECRET_KEY_BASE here isn't used. Precomiling assets doesn't use your
# secret key, but Rails will fail to initialize if it isn't set.
RUN RAILS_ENV=production PRECOMPILE=true SECRET_KEY_BASE=no \
  bundle exec rake assets:precompile
RUN rm -rf node_modules tmp/cache spec

FROM ruby:2.6.3-slim

ENV LANG en_US.UTF-8

RUN apt-get update -qq \
  && apt-get install -y postgresql-client \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1000 app && \
  useradd --uid 1000 --no-log-init --create-home --gid app app
USER app

COPY --from=compile /usr/local/bundle/ /usr/local/bundle/
COPY --from=compile --chown=app:app /app /app

ENV RACK_ENV=production
ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT true
ENV RAILS_SERVE_STATIC_FILES true
ENV EXECJS_RUNTIME Disabled

WORKDIR /app
CMD bundle exec puma -p $PORT -C /app/config/puma.rb
