.PHONY: build app run debug install clean

build:
	swift build -c release --arch arm64

app:
	./scripts/bundle.sh release

debug:
	./scripts/bundle.sh debug

run: app
	-pkill -x Pulse
	open build/Pulse.app

install: app
	-pkill -x Pulse
	rm -rf /Applications/Pulse.app
	cp -R build/Pulse.app /Applications/
	open /Applications/Pulse.app

clean:
	rm -rf .build build
