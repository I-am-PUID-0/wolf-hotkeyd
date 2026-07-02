.PHONY: bootstrap verify format lint check-format test check-whitespace compile configs shellcheck clean

PYTHON ?= python3

bootstrap:
	$(PYTHON) -m pip install --upgrade pip
	$(PYTHON) -m pip install -e .[dev]

verify: check-whitespace lint check-format compile configs test shellcheck

format:
	$(PYTHON) -m ruff check --fix .
	$(PYTHON) -m ruff format .

lint:
	$(PYTHON) -m ruff check .

check-format:
	$(PYTHON) -m ruff format --check .

check-whitespace:
	$(PYTHON) scripts/check_text.py

compile:
	$(PYTHON) -m compileall wolf_hotkeyd

configs:
	$(PYTHON) scripts/check_configs.py

test:
	$(PYTHON) -m unittest discover -s tests

shellcheck:
	bash -n actions/*.sh deploy/steam-hotkeyd-image/*.sh

clean:
	rm -rf build dist *.egg-info .pytest_cache .ruff_cache
	find . -type d -name __pycache__ -prune -exec rm -rf {} +
