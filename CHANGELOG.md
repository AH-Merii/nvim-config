# Changelog

## [0.8.0](https://github.com/AH-Merii/nvim-config/compare/v0.7.0...v0.8.0) (2026-10-18)


### Bug Fixes

* **startup:** the features load from Neovim's module cache, as spec files did ([8dbcc3b](https://github.com/AH-Merii/nvim-config/commit/8dbcc3b67f36846550c811078f3da3ffdeddf6ea))


### Restructuring

* **features:** dissolve config/autocmds.lua's eleven features ([a8807b0](https://github.com/AH-Merii/nvim-config/commit/a8807b0719627ca000158c97aba0e44ac4492ceb))
* **features:** dissolve config/keymaps.lua into the features it served ([7fcd252](https://github.com/AH-Merii/nvim-config/commit/7fcd252282107337dfffb635b6ec1accae085ad9))
* **features:** dissolve plugins/extras.lua into the features it served ([5b7a53c](https://github.com/AH-Merii/nvim-config/commit/5b7a53c162a327f58d94df8abd6321543c8c5636))
* **features:** each feature declares the snacks keys and toggles it owns ([da0f0b1](https://github.com/AH-Merii/nvim-config/commit/da0f0b19116386cceb51d80b6c487b04fd8ca50e))
* **features:** lua-dev owns the Lua and Vim script run keys ([0984396](https://github.com/AH-Merii/nvim-config/commit/09843961233fc95874c607a667d3b49d58a807ef))
* **features:** move the git, search, editing, completion and diagnostics specs into features/ ([e8058d2](https://github.com/AH-Merii/nvim-config/commit/e8058d2253c13f6162a313237df127e678918a00))
* **features:** the diagnostics feature owns how diagnostics show and their keys ([08ed424](https://github.com/AH-Merii/nvim-config/commit/08ed4247eb59e3baf24ab6206326d457f2062eb4))
* **features:** the LSP status commands are a feature, made at VeryLazy as before ([1da0058](https://github.com/AH-Merii/nvim-config/commit/1da00587cab241a72d85961445fca49b6993a5c6))
* **keys:** textobjects asks keys.which_key for which-key's preset labels ([0a696cb](https://github.com/AH-Merii/nvim-config/commit/0a696cb4c67d44cd1146885ab7929d772b77df17))
* **lang:** each language file labels its runtime ftplugin's motions ([f3bfbe4](https://github.com/AH-Merii/nvim-config/commit/f3bfbe45d59b0a7173cb6b14e6d0104dc2b7dc60))
* **lazy:** collect each adapter's plugin spec from the module it serves ([934b874](https://github.com/AH-Merii/nvim-config/commit/934b874de73a6dd4e3d4b64157934b5ee2114947))
* **lsp:** dissolve config/utils.lua; pyrefly's type-error switch is lsp/pyrefly.lua ([7761219](https://github.com/AH-Merii/nvim-config/commit/7761219f48ea6a1f36967046e38866e6e7027fc8))
* **lsp:** move the server lifecycle and the LSP keys into lsp/ ([4601717](https://github.com/AH-Merii/nvim-config/commit/46017175e1b132aa0bc6cf9a3ef13182d027221c))
* **textobjects:** move the treesitter text objects to textobjects/, unchanged ([3a099aa](https://github.com/AH-Merii/nvim-config/commit/3a099aac056a919d712b8492c5abcad8436f5ff7))
* **textobjects:** textobjects/ holds its objects' tables; treesitter's spec is a feature ([dd2bba4](https://github.com/AH-Merii/nvim-config/commit/dd2bba464067691d2d5a1256e7cf0251bea3cf18))
* **ui:** move the theme, icons, snacks and statusline specs into ui/ ([b7e67ee](https://github.com/AH-Merii/nvim-config/commit/b7e67eed6033e3bb4c6f5fe865e85df947f4562c))
* **ui:** move ui2's noice-like hooks to ui/messages, unchanged ([a653b39](https://github.com/AH-Merii/nvim-config/commit/a653b398dc192880faaa903a744015e29790cf61))
* **ui:** ui/theme gives the colorscheme's palette to the statusline ([62c2f4c](https://github.com/AH-Merii/nvim-config/commit/62c2f4cd79785efc3b4bd0d9bb438cb0df31f766))

## [0.7.0](https://github.com/AH-Merii/nvim-config/compare/v0.6.0...v0.7.0) (2026-10-17)


### Bug Fixes

* **lsp:** quitting stops every server, a busy one included, within 0.5 s ([#42](https://github.com/AH-Merii/nvim-config/issues/42)) ([7349326](https://github.com/AH-Merii/nvim-config/commit/7349326adaa3c2e8fe850287f1d892d81646827e))

## [0.6.0](https://github.com/AH-Merii/nvim-config/compare/v0.5.0...v0.6.0) (2026-10-17)


### Features

* **lsp:** gr* keys say which method no server supports instead of editing text ([baaae96](https://github.com/AH-Merii/nvim-config/commit/baaae96fe7bb3b5cb47ca8a001007c342c92e401))


### Restructuring

* **keys:** declare every key as a row in keys/, gated by needs ([da61a27](https://github.com/AH-Merii/nvim-config/commit/da61a27e9f80cb911b021ee4037104f05707d4f3))

## [0.5.0](https://github.com/AH-Merii/nvim-config/compare/v0.4.0...v0.5.0) (2026-10-17)


### Restructuring

* **ui:** the statusline is neoblocks.nvim's, drawn as lualine drew it ([#36](https://github.com/AH-Merii/nvim-config/issues/36)) ([7a98192](https://github.com/AH-Merii/nvim-config/commit/7a981921f48f41555956f14dab47e373277723b5))

## [0.4.0](https://github.com/AH-Merii/nvim-config/compare/v0.3.0...v0.4.0) (2026-10-17)


### Bug Fixes

* **lsp:** quitting Neovim leaves no server process behind, tflint's plugin child included ([#37](https://github.com/AH-Merii/nvim-config/issues/37)) ([a498512](https://github.com/AH-Merii/nvim-config/commit/a49851231e390f6b1ee729a393607acadfcaed2a))

## [0.3.0](https://github.com/AH-Merii/nvim-config/compare/v0.2.0...v0.3.0) (2026-10-17)


### Restructuring

* one module each owns formatting and linting, and the facts read their plans ([#34](https://github.com/AH-Merii/nvim-config/issues/34)) ([0c1277f](https://github.com/AH-Merii/nvim-config/commit/0c1277f674e982eccd74d2bc9bf1ef5652ff9913))

## [0.2.0](https://github.com/AH-Merii/nvim-config/compare/v0.1.0...v0.2.0) (2026-10-17)


### Restructuring

* **ui:** the statusline draws each buffer's facts from ui/facts ([#32](https://github.com/AH-Merii/nvim-config/issues/32)) ([98bd4c0](https://github.com/AH-Merii/nvim-config/commit/98bd4c0e9681645f937dc1f0dd4b6915985076d8))

## 0.1.0 (2026-10-17)


### Restructuring

* **lang:** one file per language feeds every plugin's language tables ([#30](https://github.com/AH-Merii/nvim-config/issues/30)) ([2be6db3](https://github.com/AH-Merii/nvim-config/commit/2be6db3930c0cfa6b80d3faa5622704b3eceea7b))
