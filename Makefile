ifeq ($(shell swift format --version >/dev/null 2>&1 && echo yes),yes)
FORMAT := swift format
else
FORMAT := xcrun swift-format
endif

.PHONY: build debug run test format format-check dmg

build:
	./build_app.sh

dmg:
	./scripts/make-dmg.sh

debug:
	swift build

run: debug
	"$$(swift build --show-bin-path)/opaq"

test:
	swift test

format:
	$(FORMAT) format --configuration .swift-format --in-place --recursive Sources Tests

format-check:
	$(FORMAT) lint --configuration .swift-format --strict --recursive Sources Tests
