# Changelog

## [1.1.0](https://github.com/simifalaye/minibuffer.nvim/compare/v1.0.0...v1.1.0) (2026-09-02)


### Features

* Improve statusline integration and add lualine support ([#16](https://github.com/simifalaye/minibuffer.nvim/issues/16)) ([cb9e74e](https://github.com/simifalaye/minibuffer.nvim/commit/cb9e74e46454b036867ffe2b1cd8b06603845d6c))

## 1.0.0 (2026-08-31)


### ⚠ BREAKING CHANGES

* config handling/validation and health check additions
* Clean up session APIs
* Refactor/improve codebase

### Features

* Add cmd autotrigger configuration option ([8d64239](https://github.com/simifalaye/minibuffer.nvim/commit/8d64239f22a41466105982caa4d3ca2f57ff6f62))
* Add more example pickers from my local config ([f9a89af](https://github.com/simifalaye/minibuffer.nvim/commit/f9a89af35c0b8ff5d7808d5738b6cd61d6d32daf))
* allow user changes to cmdheight on running instance ([411761a](https://github.com/simifalaye/minibuffer.nvim/commit/411761acde7a8f7edccbc27189cd149d8d778dbc))
* close minibuffer on focus lost ([3e71ce0](https://github.com/simifalaye/minibuffer.nvim/commit/3e71ce06d128ab157712253e0bd740f502f087f4))
* config handling/validation and health check additions ([bbc7d56](https://github.com/simifalaye/minibuffer.nvim/commit/bbc7d5601f736654429e66c0d89668f05fe07915))
* further cmdline improvements ([ded09e1](https://github.com/simifalaye/minibuffer.nvim/commit/ded09e17a43eb526ec7a0b9f699d3065557c35bc))
* improve cmd window handling ([2543714](https://github.com/simifalaye/minibuffer.nvim/commit/2543714d9136e8532b42b6d830b7d3e9946b5783))
* improve dynamic window resizing and make it an optional feature ([a4bba77](https://github.com/simifalaye/minibuffer.nvim/commit/a4bba77540cf4395484bda44743a4c99d95e93cb))
* Improve resume for resumable sessions ([4df5087](https://github.com/simifalaye/minibuffer.nvim/commit/4df5087b7a48cb31734cc3cf28d0c40707eb5728))
* Make examples builtin ([5452652](https://github.com/simifalaye/minibuffer.nvim/commit/54526527d75ec7e943aedd02c6b7c4e5aa550486))
* Refactor/improve codebase ([f3c9c1f](https://github.com/simifalaye/minibuffer.nvim/commit/f3c9c1fbcf76e2e3f1b3d07265348d1f4bba4311))
* Simplify integration with other plugins ([8ab8748](https://github.com/simifalaye/minibuffer.nvim/commit/8ab8748c207ceb1de18f3476a5cb5879759b97cc))
* Support multiple window config markers ([14b499c](https://github.com/simifalaye/minibuffer.nvim/commit/14b499ccc1c88d965634f757e52e772fb9b40853))
* support restoring selected index for select and input sessions on resume ([1a7721e](https://github.com/simifalaye/minibuffer.nvim/commit/1a7721e33a0b177dea1c48dc4cbc687db577162e))
* Use ui_attach handlers for cmd ([b14263f](https://github.com/simifalaye/minibuffer.nvim/commit/b14263f01c2c1dcffa88ef63ff612ae50d7cccca))


### Bug Fixes

* access table properties before calling lower in oldfiles filter ([3011b83](https://github.com/simifalaye/minibuffer.nvim/commit/3011b830253530dad985dba5e14a320276be1502))
* Add C-c mapping to select input ([8fb32f1](https://github.com/simifalaye/minibuffer.nvim/commit/8fb32f132d2bd16218a2fb8e62fe91a3e3191d13))
* cmd dynamic height ([3b1247c](https://github.com/simifalaye/minibuffer.nvim/commit/3b1247c41218de7cdcca972ff8ee2ef6d130f42e))
* commit doc tags file ([f86c36a](https://github.com/simifalaye/minibuffer.nvim/commit/f86c36a2f9d54962921d52e19893b0d1c43a61c9))
* correct buffer spit code and fetch err handling ([dcc2604](https://github.com/simifalaye/minibuffer.nvim/commit/dcc26041b1d329e327317b1a85f90e5a6b6d369d))
* Correct scratch API documentation and ui_select items ([73174f4](https://github.com/simifalaye/minibuffer.nvim/commit/73174f4258cee123d4613203eaebcebb519765f8))
* Default autotrigger to true ([ee96338](https://github.com/simifalaye/minibuffer.nvim/commit/ee96338317acd547d1329d0d69893dd7bd37225e))
* Don't force delete scratch buffers ([c999de7](https://github.com/simifalaye/minibuffer.nvim/commit/c999de7ad851f2cc8bc247738d99a0d80624c430))
* don't run matchfuzzy on files pull ([02ccc38](https://github.com/simifalaye/minibuffer.nvim/commit/02ccc38feb7f7896a1419d9cf9d22982dd20ad4a)), closes [#5](https://github.com/simifalaye/minibuffer.nvim/issues/5)
* filter only `pum` from wildoptions ([63ed47c](https://github.com/simifalaye/minibuffer.nvim/commit/63ed47c7d0bc0f9ea53b3f657fffb7f04d013053))
* Handle brace expansion error from vim.fn.getcompletion with pcall ([61e8b5e](https://github.com/simifalaye/minibuffer.nvim/commit/61e8b5e478aa4f539f43fafcb9462f4bbf0d4185))
* Handle brace expansion error from vim.fn.getcompletion with pcall ([d76f352](https://github.com/simifalaye/minibuffer.nvim/commit/d76f352baa7e53b180143dc8a403406622c09af4))
* instantiate ScratchSession in init.lua general entrypoint ([2495e97](https://github.com/simifalaye/minibuffer.nvim/commit/2495e9791f2ae579c59afa90e901caadadebaf6b))
* join cwd with selected file paths on selection ([9e491f9](https://github.com/simifalaye/minibuffer.nvim/commit/9e491f9ecda324ff7f72c1e5244b90fb6cfab206))
* make sure input is restored on resumed select sessions ([7df62d2](https://github.com/simifalaye/minibuffer.nvim/commit/7df62d219d83e9b8776e40ea792db161106320eb))
* Make window utilities tabpage aware ([35ea6af](https://github.com/simifalaye/minibuffer.nvim/commit/35ea6af9af98cd7b808f7b4af6036536f79f295e))
* pass unwrapped item and index to vim.ui.select callback ([b489cd7](https://github.com/simifalaye/minibuffer.nvim/commit/b489cd7d23243a94a5f707509a78faf5d380ad8f))
* pcall cmd window api calls ([033534e](https://github.com/simifalaye/minibuffer.nvim/commit/033534e01198643d96f4cc293b6dbe0f57f528bf))
* recognise `:=` as a lua command prefix ([593af61](https://github.com/simifalaye/minibuffer.nvim/commit/593af613597df47a047418a904a2eacb7fc95af6))
* Remove un-needed vim.schedule on files example ([4e72403](https://github.com/simifalaye/minibuffer.nvim/commit/4e724038e4fa0f0adbbf41d438a4a524982071b5))
* remove window resizing for cmd view ([13ac537](https://github.com/simifalaye/minibuffer.nvim/commit/13ac5379b443e0407c28acc1a469b394d5ec782e))
* session close/cancel callback timing ([4d088e0](https://github.com/simifalaye/minibuffer.nvim/commit/4d088e0dd1006d419f788d9e7a84ee19e36ae7f9))
* use '=' as a cmd completion boundary ([f4824b9](https://github.com/simifalaye/minibuffer.nvim/commit/f4824b93eb8553e662339cd22db88135bc038ecc))
* Use separate entry win for interactive sessions ([266dbb1](https://github.com/simifalaye/minibuffer.nvim/commit/266dbb111f5e4ab7287520f66515e26094228c24))
* use string concatenation operator when accepting input suggestions ([3e0d32d](https://github.com/simifalaye/minibuffer.nvim/commit/3e0d32defe59f5e9d986add35cdca228a8ab6406))


### Code Refactoring

* Clean up session APIs ([304f8c2](https://github.com/simifalaye/minibuffer.nvim/commit/304f8c27e183a567d9915b6a587e9b3a587bbf4a))

## Changelog

All notable changes to this project will be documented in this file.
