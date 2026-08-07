# One reproducible image contains Jupyter, Python/MEFISTO, R/TEMPTED,
# plotting tools, and both notebook kernels. No packages are installed manually
# after the container starts.
FROM rocker/r-ver:4.4.1

ARG DEBIAN_FRONTEND=noninteractive

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# System libraries required by the Python scientific stack, MOFA/MEFISTO,
# TEMPTED, and the R tidyverse plotting packages used by notebook 06.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv python3-dev \
    build-essential gfortran git ca-certificates curl \
    libblas-dev liblapack-dev libhdf5-dev libgsl-dev \
    libcurl4-openssl-dev libssl-dev libxml2-dev libgit2-dev \
    libzmq3-dev libfontconfig1-dev libfreetype6-dev libpng-dev \
    libjpeg-dev libtiff-dev libicu-dev libharfbuzz-dev libfribidi-dev \
    && rm -rf /var/lib/apt/lists/*

# Create a dedicated Python environment. The PATH setting above makes both
# `python` and `pip` available inside the container.
RUN python3 -m venv "$VIRTUAL_ENV" \
    && "$VIRTUAL_ENV/bin/python" -m pip install --upgrade pip setuptools wheel \
    && ln -sf "$VIRTUAL_ENV/bin/python" /usr/local/bin/python \
    && ln -sf "$VIRTUAL_ENV/bin/pip" /usr/local/bin/pip

WORKDIR /workspace

# Install the project's pinned Python dependencies, then add the packages used
# by the current plotting notebooks. Installing these here makes them part of
# the deployed image rather than a per-container manual change.
COPY requirements.txt /tmp/requirements.txt
RUN python -m pip install -r /tmp/requirements.txt \
    && python -m pip install \
        "ipython>=8.26,<9" \
        "biopython>=1.84,<2" \
    && python -m ipykernel install \
        --sys-prefix \
        --name python3 \
        --display-name "Python 3"

# Install every R package required by the current R notebooks during the image
# build. Notebook 06 specifically requires dplyr, tidyr, and ggplot2.
RUN R -e "options(repos=c(CRAN='https://cloud.r-project.org'), Ncpus=max(1L, parallel::detectCores()-1L)); \
    packages <- c('IRkernel','nnet','tempted','dplyr','tidyr','ggplot2'); \
    missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly=TRUE)]; \
    if (length(missing)) install.packages(missing); \
    IRkernel::installspec(user=FALSE)"

# Fail the image build immediately if a required Python or R dependency is
# missing. This prevents deploying a container that starts but cannot run the
# notebooks.
RUN python -c "import numpy, pandas, scipy, sklearn, matplotlib, h5py, anndata, muon, mofapy2; from Bio import Phylo" \
    && R -e "stopifnot(all(vapply(c('IRkernel','nnet','tempted','dplyr','tidyr','ggplot2'), requireNamespace, logical(1), quietly=TRUE)))"

# Project files are copied for image completeness. The Compose bind mount keeps
# local notebooks and data editable while the installed software remains baked
# into the image.
COPY . /workspace

EXPOSE 8888

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
    CMD curl --fail --silent "http://localhost:8888/api?token=workflow" >/dev/null || exit 1

CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root", "--ServerApp.token=workflow", "--ServerApp.root_dir=/workspace"]
