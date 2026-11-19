# SPDX-License-Identifier: MIT
# Makefile -- MM-IV-DIAG diagnostic ROM for the Mephisto MM IV / MM V.
#
# Requirements: cc65 (ca65, ld65, ar65), GNU make, Perl v5.40+.
#
# Targets:
#   all    ROM image (default), instruction-set check, image verification
#   clean  remove build/

VERSION := $(shell cat VERSION)
NAME    := mm-iv-diag

BUILD   := build
OBJ     := $(BUILD)/obj
ROM     := $(BUILD)/$(NAME)-$(VERSION).bin
MAP     := $(BUILD)/$(NAME)-$(VERSION).map
LABELS  := $(BUILD)/$(NAME)-$(VERSION).lbl
DBG     := $(BUILD)/$(NAME)-$(VERSION).dbg
HAL_LIB := $(BUILD)/hal.lib
VERSION_INC := $(BUILD)/version.inc

CA65 ?= ca65
LD65 ?= ld65
AR65 ?= ar65
PERL ?= perl

# 65SC02: the common 65C02 subset. Rejects the Rockwell/WDC bit
# instructions (RMB/SMB/BBR/BBS) and WAI/STP, which the G65SC02 lacks
# (docs/hardware.md; checked by isa-check).
CPU     := 65SC02
CAFLAGS := --cpu $(CPU) -I include -I $(BUILD) -g
LDFLAGS := -C cfg/rom.cfg

# Run a cc65 tool and fail on any warning (ca65/ld65 2.19 have no option
# to treat warnings as errors).
strict = out=$$($(1) 2>&1); st=$$?; [ -z "$$out" ] || echo "$$out"; \
  [ $$st -eq 0 ] && ! echo "$$out" | grep -qi 'warning'

RUNTIME_SRC := $(wildcard runtime/*.s)
HAL_SRC     := $(wildcard hal/*.s)
DIAG_SRC    := $(wildcard diag/*.s)
ALL_SRC     := $(RUNTIME_SRC) $(HAL_SRC) $(DIAG_SRC)

RUNTIME_OBJ := $(RUNTIME_SRC:%.s=$(OBJ)/%.o)
HAL_OBJ     := $(HAL_SRC:%.s=$(OBJ)/%.o)
DIAG_OBJ    := $(DIAG_SRC:%.s=$(OBJ)/%.o)
LINK_LIBS   := $(if $(HAL_OBJ),$(HAL_LIB))

.PHONY: all rom verify isa-check clean FORCE
.DEFAULT_GOAL := all

all: isa-check rom verify

rom: $(ROM)

# --- Version include ------------------------------------------------------
# The timestamp in the ident block is the release date from RELEASE_DATE,
# never the current time, so every build of a release is bit-identical;
# SOURCE_DATE_EPOCH overrides it explicitly. The rule runs on every build
# (FORCE) so an override takes effect; mkversion.pl rewrites the file only
# when its content changes.

$(VERSION_INC): VERSION RELEASE_DATE tools/mkversion.pl FORCE | $(BUILD)
	$(PERL) tools/mkversion.pl VERSION RELEASE_DATE $@

FORCE:

# --- Assemble, archive, link ----------------------------------------------

$(OBJ)/%.o: %.s | $(VERSION_INC)
	@mkdir -p $(dir $@)
	@echo "ca65 $<"
	@$(call strict,$(CA65) $(CAFLAGS) --create-dep $(@:.o=.d) -l $(@:.o=.lst) -o $@ $<)

$(HAL_LIB): $(HAL_OBJ)
	rm -f $@
	$(AR65) a $@ $^

$(ROM): $(RUNTIME_OBJ) $(DIAG_OBJ) $(LINK_LIBS) cfg/rom.cfg tools/romtool.pl
	@echo "ld65 $@"
	@$(call strict,$(LD65) $(LDFLAGS) -m $(MAP) -Ln $(LABELS) --dbgfile $(DBG) \
	  -o $@.tmp $(RUNTIME_OBJ) $(DIAG_OBJ) $(LINK_LIBS))
	$(PERL) tools/romtool.pl patch $@.tmp
	mv $@.tmp $@

verify: $(ROM)
	$(PERL) tools/romtool.pl verify $(ROM)

$(BUILD):
	mkdir -p $@

-include $(wildcard $(OBJ)/*/*.d)

# --- Instruction-set check ------------------------------------------------
# Each forbidden instruction must fail to assemble with CAFLAGS, and no
# source may switch the CPU with a directive.

ISA_FORBIDDEN := 'rmb0 $$10' 'smb7 $$10' 'l: bbr0 $$10, l' 'l: bbs7 $$10, l' 'stp' 'wai'
CPU_DIRECTIVES := \.(setcpu|p02|p02x|pc02|psc02|p816|p4510|p6280|pce02|pdtv|pm740|pwc02|psweet16)\b

isa-check: | $(BUILD)
	@for i in $(ISA_FORBIDDEN); do \
	  printf '.segment "CODE"\n%s\n' "$$i" > $(BUILD)/isa-check.s; \
	  if $(CA65) $(CAFLAGS) -o $(BUILD)/isa-check.o $(BUILD)/isa-check.s 2>/dev/null; then \
	    echo "isa-check: FAIL, '$$i' assembled with --cpu $(CPU)"; exit 1; \
	  fi; \
	done
	@printf '.segment "CODE"\n  lda #0\n  bra *\n' > $(BUILD)/isa-check.s
	@$(CA65) $(CAFLAGS) -o $(BUILD)/isa-check.o $(BUILD)/isa-check.s || \
	  { echo "isa-check: FAIL, 65C02 instructions rejected"; exit 1; }
	@if grep -nEi '^[[:space:]]*$(CPU_DIRECTIVES)' $(ALL_SRC) include/*.inc; then \
	  echo "isa-check: FAIL, CPU directive in project source"; exit 1; \
	fi
	@rm -f $(BUILD)/isa-check.s $(BUILD)/isa-check.o
	@echo "isa-check: OK (6 forbidden instructions rejected)"

clean:
	rm -rf $(BUILD)
