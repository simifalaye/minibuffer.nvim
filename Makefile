.PHONY: dl-deps doc check-doc test coverage-html luacheck check-stylua stylua check-mdformat mdformat check

dl-deps:
	@clone() { \
		repo="$$1"; \
		dest="$$2"; \
		if [ -d "$$dest/.git" ]; then return; fi; \
		echo "Cloning $$repo -> $$dest"; \
		git clone --quiet "$$repo" "$$dest"; \
	}; \
	clone git@github.com:Bilal2453/luvit-meta.git .deps/luvit-meta & \
	clone git@github.com:LuaCATS/busted.git .deps/busted & \
	clone git@github.com:LuaCATS/luassert.git .deps/luassert & \
	wait

doc:
	@command -v vimcats >/dev/null 2>&1 || { \
		echo "vimcats is not installed."; \
		echo "Install it from https://github.com/lumen-oss/vimcats"; \
		exit 1; \
	}
	@vimcats \
		lua/minibuffer/init.lua \
		lua/minibuffer/types.lua \
		lua/minibuffer/config/init.lua \
		lua/minibuffer/sessions/* \
		> $(or $(DOC),doc/minibuffer.txt)
	@nvim --clean -es \
		-c 'helptags doc' \
		-c 'qa'

check-doc:
	@tmp=$$(mktemp); \
	trap 'rm -f "$$tmp"' EXIT; \
	$(MAKE) doc DOC="$$tmp" >/dev/null; \
	if ! diff -u doc/minibuffer.txt "$$tmp"; then \
		echo ""; \
		echo "Documentation is out of date. Re-run 'make doc'"; \
		exit 1; \
	fi

test: dl-deps
	@command -v busted >/dev/null 2>&1 || { \
		echo "busted is not installed."; \
		echo "Install it with: luarocks install --local busted"; \
		exit 1; \
	}
	busted .

coverage-html: dl-deps
	@command -v luacov >/dev/null 2>&1 || { \
		echo "luacov is not installed."; \
		echo "Install it with: luarocks install --local luacov"; \
		exit 1; \
	}
	@command -v luacov-multiple >/dev/null 2>&1 || { \
		echo "luacov-multiple is not installed."; \
		echo "Install it with: luarocks install --local luacov-multiple"; \
		exit 1; \
	}
	nvim -u NONE -U NONE -N -i NONE --headless \
		-c "luafile scripts/luacov.lua" \
		-c "quit"
	luacov --reporter multiple

luacheck:
	@command -v luacheck >/dev/null 2>&1 || { \
		echo "luacheck is not installed."; \
		echo "Install it with: luarocks install luacheck"; \
		exit 1; \
	}
	luacheck lua plugin scripts spec

check-stylua:
	@command -v stylua >/dev/null 2>&1 || { \
		echo "stylua is not installed."; \
		echo "Install it from https://github.com/JohnnyMorganz/StyLua"; \
		exit 1; \
	}
	stylua lua plugin scripts spec --color always --check

stylua:
	@command -v stylua >/dev/null 2>&1 || { \
		echo "stylua is not installed."; \
		echo "Install it from https://github.com/JohnnyMorganz/StyLua"; \
		exit 1; \
	}
	stylua lua plugin scripts spec

check-mdformat:
	@command -v mdformat >/dev/null 2>&1 || { \
		echo "mdformat is not installed."; \
		echo "Install it from https://github.com/hukkin/mdformat"; \
		exit 1; \
	}
	mdformat --check README.md

mdformat:
	@command -v mdformat >/dev/null 2>&1 || { \
		echo "mdformat is not installed."; \
		echo "Install it from https://github.com/hukkin/mdformat"; \
		exit 1; \
	}
	mdformat README.md

check: luacheck check-stylua check-mdformat check-doc test
