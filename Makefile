.PHONY: test app install run

test:
	swift test

app:
	scripts/build-app.sh

install:
	scripts/build-app.sh --install

# Pinned open, for UI work.
run:
	swift build && NOTCH_LIMITS_PINNED=1 .build/debug/NotchLimits
