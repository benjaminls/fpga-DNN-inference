VIVADO ?= vivado

.PHONY: build clean

build:
	$(VIVADO) -mode batch -source scripts/build_vivado.tcl

clean:
	rm -rf build
