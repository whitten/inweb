# This makefile was automatically written by inweb -makefile
# and is not intended for human editing

ME = inweb
SAFETYCOPY = $(ME)/Tangled/inweb_dev

-include $(ME)/platform-settings.mk

.PHONY: all

all: $(ME)/platform-settings.mk $(ME)/Tangled/$(ME) $(ME)/Manual.html

$(ME)/Tangled/$(ME): $(ME)/Contents.w $(ME)/Chapter*/*.w $(ME)/foundation-module/Contents.w $(ME)/foundation-module/Chapter*/*.w
	$(call make-me)

$(ME)/Manual.html: $(ME)/Contents.w $(ME)/Preliminaries/*.w 
	$(ME)/Tangled/$(ME) $(ME) -weave P -weave-to $(ME)/Manual.html

.PHONY: force
force: $(ME)/platform-settings.mk
	$(call make-me)

.PHONY: macos
macos: 
	cp -f $(ME)/Materials/macos-make-settings.mk $(ME)/platform-settings.mk
	echo "=== Platform set to 64-bit MacOS. Now: make -f inweb/inweb.mk initial ==="

.PHONY: macos32
macos32:
	cp -f $(ME)/Materials/macos32-make-settings.mk $(ME)/platform-settings.mk
	echo "=== Platform set to 32-bit MacOS. Now: make -f inweb/inweb.mk initial ==="

.PHONY: windows
windows: 
	cp -f $(ME)/Materials/windows-make-settings.mk $(ME)/platform-settings.mk
	echo "=== Platform set to Windows. Now: make -f inweb/inweb.mk initial ==="

.PHONY: linux
linux: 
	cp -f $(ME)/Materials/linux-make-settings.mk $(ME)/platform-settings.mk
	echo "=== Platform set to Linux. Now: make -f inweb/inweb.mk initial ==="

.PHONY: unix
unix: 
	cp -f $(ME)/Materials/unix-make-settings.mk $(ME)/platform-settings.mk
	echo "=== Platform set to generic Unix (non-Linux, non-MacOS, non-Android). Now: make -f inweb/inweb.mk initial ==="

.PHONY: android
android: 
	cp -f $(ME)/Materials/android-make-settings.mk $(ME)/platform-settings.mk
	echo "=== Platform set to Android. Now: make -f inweb/inweb.mk initial ==="

.PHONY: initial
initial: $(ME)/platform-settings.mk
	$(call make-me-once-tangled)

.PHONY: safe
safe:
	$(call make-me-using-safety-copy)

define make-me-once-tangled
	$(CC) -o $(ME)/Tangled/$(ME).o $(ME)/Tangled/$(ME).c
	$(LINK) -o $(ME)/Tangled/$(ME) $(ME)/Tangled/$(ME).o $(LINKEROPTS)
endef

define make-me
	$(ME)/Tangled/$(ME) $(ME) -tangle
	$(call make-me-once-tangled)
endef

define make-me-using-safety-copy
	$(SAFETYCOPY) $(ME) -tangle
	$(call make-me-once-tangled)
endef

.PHONY: test
test:
	$(INTEST) -from $(ME) all

.PHONY: pages
pages:
	mkdir -p $(ME)/docs/inweb
	mkdir -p $(ME)/docs/foundation-module
	mkdir -p $(ME)/docs/foundation-test
	$(INWEB) $(ME) -weave-docs -weave-into $(ME)/docs/inweb
	$(INWEB) $(ME)/foundation-module -weave-docs -weave-into $(ME)/docs/foundation-module
	$(INWEB) $(ME)/foundation-test -weave-docs -weave-into $(ME)/docs/foundation-test

.PHONY: clean
clean:
	$(call clean-up)

.PHONY: purge
purge:
	$(call clean-up)

define clean-up
	rm -f $(ME)/Tangled/*.o
	rm -f $(ME)/Tangled/*.h
endef

