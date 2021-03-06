# Settings
JEKYLL=jekyll
CHROME=google-chrome-stable
TUTORIALS=$(shell find _site/training-material -name 'tutorial.html' | sed 's/_site\/training-material\///')
SLIDES=$(shell find _site/training-material -name 'slides.html' | sed 's/_site\/training-material\///')
SLIDES+=$(shell find _site/training-material/*/*/slides/* | sed 's/_site\/training-material\///')
SITE_URL=http://localhost:4000/training-material
PDF_DIR=_pdf
REPO=$(shell echo "$${ORIGIN_REPO:-galaxyproject/training-material}")
BRANCH=$(shell echo "$${ORIGIN_BRANCH:-master}")
MINICONDA_URL=https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh
SHELL=bash
RUBY_VERSION=2.4.4

ifeq ($(shell uname -s),Darwin)
	CHROME=/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome
	MINICONDA_URL=https://repo.continuum.io/miniconda/Miniconda3-latest-MacOSX-x86_64.sh
endif

CONDA=$(shell which conda)
ifeq ($(CONDA),)
	CONDA=${HOME}/miniconda3/bin/conda
endif

default: help

install-conda: ## install Miniconda
	curl $(MINICONDA_URL) -o miniconda.sh
	bash miniconda.sh -b
.PHONY: install-conda

create-env: ## create conda environment
	if ${CONDA} env list | grep '^galaxy_training_material'; then \
	    ${CONDA} env update -f environment.yml; \
	else \
	    ${CONDA} env create -f environment.yml; \
	fi
.PHONY: create-env

ACTIVATE_ENV=. $(dir ${CONDA})activate galaxy_training_material

install: clean ## install dependencies
	( $(ACTIVATE_ENV) && \
	  npm install decktape && \
	  gem install awesome_bot bundler html-proofer jekyll jekyll-feed pkg-config:'~> 1.1' && \
	  gem install nokogiri:'1.8.2' -- --use-system-libraries --with-xml=$(CONDA_PREFIX)/lib \
	)
.PHONY: install

serve: ## run a local server}
	( $(ACTIVATE_ENV) && \
	  ${JEKYLL} serve --strict_front_matter -d _site/training-material \
	)
.PHONY: serve

detached-serve: clean ## run a local server in detached mode
	( $(ACTIVATE_ENV) && \
	  ${JEKYLL} serve --strict_front_matter --detach -d _site/training-material \
	)
.PHONY: detached-serve

build: clean ## build files but do not run a server
	( $(ACTIVATE_ENV) && \
	  ${JEKYLL} build --strict_front_matter -d _site/training-material \
	)
.PHONY: build

check-frontmatter: build ## Validate the frontmatter
	( $(ACTIVATE_ENV) && \
	  find topics/ -name tutorial.md -or -name slides.html | \
	    xargs -n1 ruby bin/validate-frontmatter.rb \
	)
.PHONY: check-frontmatter

check-html: build ## validate HTML
	( $(ACTIVATE_ENV) && \
	  htmlproofer \
	      --assume-extension \
	      --http-status-ignore 405,503,999 \
	      --url-ignore "/.*localhost.*/","/.*vimeo\.com.*/","/.*gitter\.im.*/","/.*drmaa\.org.*/" \
	      --url-swap "github.com/galaxyproject/training-material/tree/master:github.com/${REPO}/tree/${BRANCH}" \
	      --file-ignore "/.*\/files\/.*/","/.*\/node_modules\/.*/" \
	      --allow-hash-href \
	      ./_site \
	)
.PHONY: check-html

check-html-internal: build ## validate HTML (internal links only)
	( $(ACTIVATE_ENV) && \
	  htmlproofer \
	      --assume-extension \
	      --http-status-ignore 405,503,999 \
	      --url-ignore "/.*localhost.*/","/.*vimeo\.com.*/","/.*gitter\.im.*/","/.*drmaa\.org.*/" \
	      --url-swap "github.com/galaxyproject/training-material/tree/master:github.com/${REPO}/tree/${BRANCH}" \
	      --file-ignore "/.*\/files\/.*/","/.*\/node_modules\/.*/" \
	      --disable-external \
	      --allow-hash-href \
	      ./_site \
	)
.PHONY: check-html-internal

check-slides: build  ## check the markdown-formatted links in slides
	( $(ACTIVATE_ENV) && \
	  find _site -path "**/slides*.html" \
	      | xargs -L 1 -I '{}' sh -c "awesome_bot \
	          --allow 405 \
	          --allow-redirect \
	          --white-list localhost,127.0.0.1,fqdn,vimeo.com,drmaa.com \
	          --allow-ssl \
	          --allow-dupe \
	          --skip-save-results \
	          -f {}" \
	)
.PHONY: check-slides

check-yaml: ## lint yaml files
	( $(ACTIVATE_ENV) && \
	  find . -name "*.yaml" | xargs -L 1 -I '{}' sh -c "yamllint {}" \
	  find topics -name '*.yml' | xargs -L 1 -I '{}' sh -c "yamllint {}" \
	)
.PHONY: check-yaml

check: check-yaml check-html check-slides  ## run all checks
.PHONY: check

check-links-gh-pages:  ## validate HTML on gh-pages branch (for daily cron job)
	( $(ACTIVATE_ENV) && \
	  htmlproofer \
	      --assume-extension \
	      --http-status-ignore 405,503,999 \
	      --url-ignore "/.*localhost.*/","/.*vimeo\.com.*/","/.*gitter\.im.*/","/.*drmaa\.org.*/" \
	      --file-ignore "/.*\/files\/.*/" \
	      --allow-hash-href \
	      . && \
	  find . -path "**/slides*.html" \
	      | xargs -L 1 -I '{}' sh -c "awesome_bot \
	          --allow 405 \
	          --allow-redirect \
	          --white-list localhost,127.0.0.1,fqdn,vimeo.com,drmaa.com \
	          --allow-ssl \
	          --allow-dupe \
	          --skip-save-results \
	          -f {}" \
	)
.PHONY: check-links-gh-pages

pdf: detached-serve ## generate the PDF of the tutorials and slides
	mkdir -p _pdf
	@for t in $(TUTORIALS); do \
		name="$(PDF_DIR)/$$(echo $$t | tr '/' '-' | sed -e 's/html/pdf/' -e 's/topics-//' -e 's/tutorials-//')"; \
		${CHROME} \
            --headless \
            --disable-gpu \
            --print-to-pdf="$$name" \
            "$(SITE_URL)/$$t?with-answers" \
            2> /dev/null ; \
    done
	@for s in $(SLIDES); do \
		name="$(PDF_DIR)/$$(echo $$s | tr '/' '-' | sed -e 's/html/pdf/' -e 's/topics-//' -e 's/tutorials-//')"; \
		`npm bin`/decktape \
			automatic \
			"$(SITE_URL)/$$s?with-answers" \
			"$$name" \
            2> /dev/null ; \
	done
	pkill -f jekyll
.PHONY: pdf

annotate: ## annotate the tutorials with usable Galaxy instances and generate badges
	python bin/add_galaxy_instance_annotations.py
	python bin/add_galaxy_instance_badges.py
.PHONY: annotate

clean: ## clean up junk files
	@rm -rf _site
	@rm -rf .sass-cache
	@rm -rf .bundle
	@rm -rf vendor
	@rm -rf node_modules
	@find . -name .DS_Store -exec rm {} \;
	@find . -name '*~' -exec rm {} \;
.PHONY: clean

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
.PHONY: help
