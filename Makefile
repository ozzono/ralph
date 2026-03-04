.PHONY: build build-flutter

build:
	docker build -f Dockerfile -t ralph-loop:latest .

build-flutter:
	docker build -f Dockerfile.flutter -t ralph-flutter:latest .
