# Start with Rocker's tidyverse image
FROM rocker/tidyverse:latest

# Install system libraries and Shiny Server dependencies
RUN apt-get update && apt-get install -y \
    gdebi-core \
    sudo \
    pandoc \
    pandoc-citeproc \
    libcairo2-dev \
    libxt-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    sqlite3 \
    python3 python3-pip \
    && apt-get clean

# Install Shiny Server (official .deb package)
RUN wget https://download3.rstudio.org/ubuntu-14.04/x86_64/shiny-server-1.5.20.1002-amd64.deb && \
    gdebi -n shiny-server-1.5.20.1002-amd64.deb && \
    rm shiny-server-1.5.20.1002-amd64.deb

# Python dependencies
RUN pip3 install requests

# Install R packages NOT included in tidyverse
RUN R -e "install.packages(c( \
    'knitr', \
    'DBI', \
    'RSQLite', \
    'flexdashboard', \
    'shiny', \
    'leaflet', \
    'tidygeocoder', \
    'httr', \
    'jsonlite' \
), repos='https://cloud.r-project.org/')"

# App directory
RUN mkdir -p /srv/shiny-server/app

# Copy your project
COPY . /srv/shiny-server/app

# Build SQLite database using Python
WORKDIR /srv/shiny-server/app
RUN python3 read_api.py

# Expose Shiny Server port
EXPOSE 3838

# Start Shiny Server
CMD ["/usr/bin/shiny-server"]
