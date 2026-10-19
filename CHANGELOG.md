# Changelog

## [1.3.0](https://github.com/AH-Merii/nvim-config/compare/v1.2.0...v1.3.0) (2026-10-19)


### Features

* **ui:** the statusline names each formatter's and linter's tool once ([#80](https://github.com/AH-Merii/nvim-config/issues/80)) ([290ad10](https://github.com/AH-Merii/nvim-config/commit/290ad100e98aa7c57fb82443ff5b695f48f202d8))

## [1.2.0](https://github.com/AH-Merii/nvim-config/compare/v1.1.0...v1.2.0) (2026-10-19)


### Bug Fixes

* **ui:** every hidden character is drawn in onedark's dim grey ([#77](https://github.com/AH-Merii/nvim-config/issues/77)) ([9a3fa00](https://github.com/AH-Merii/nvim-config/commit/9a3fa000eac22244dada645449d5f3d7b236a19d))

## [1.1.0](https://github.com/AH-Merii/nvim-config/compare/v1.0.0...v1.1.0) (2026-10-19)


### Bug Fixes

* **treesitter:** python's new line skips brackets in strings and comments ([#75](https://github.com/AH-Merii/nvim-config/issues/75)) ([722cb60](https://github.com/AH-Merii/nvim-config/commit/722cb60bb8b97136f6dccf640734eee3ece9a22b))

## [1.0.0](https://github.com/AH-Merii/nvim-config/compare/v0.16.0...v1.0.0) (2026-10-19)


### Features

* **parsers:** install a buffer's treesitter parsers when it first needs them ([#73](https://github.com/AH-Merii/nvim-config/issues/73)) ([2638d32](https://github.com/AH-Merii/nvim-config/commit/2638d328fed39fc0dcaed7ba7c6c32f5a821e746))


### Chores

* release 1.0.0, the rearchitecture's first complete design ([#70](https://github.com/AH-Merii/nvim-config/issues/70)) ([f45107b](https://github.com/AH-Merii/nvim-config/commit/f45107bb577c8b87337654700b9241d73fddf597))

## [0.16.0](https://github.com/AH-Merii/nvim-config/compare/v0.15.0...v0.16.0) (2026-10-18)


### Restructuring

* **treesitter:** drop the build's master and lazy.nvim migration code ([#71](https://github.com/AH-Merii/nvim-config/issues/71)) ([88888f7](https://github.com/AH-Merii/nvim-config/commit/88888f7d308c3429c9a5766e119ccc47692f3652))

## [0.15.0](https://github.com/AH-Merii/nvim-config/compare/v0.14.0...v0.15.0) (2026-10-18)


### Features

* **tools:** installs never write your global mise config, and can target one project ([#66](https://github.com/AH-Merii/nvim-config/issues/66)) ([c3f5887](https://github.com/AH-Merii/nvim-config/commit/c3f5887b708dfd463acb30ec479fb4ad882b721f))

## [0.14.0](https://github.com/AH-Merii/nvim-config/compare/v0.13.0...v0.14.0) (2026-10-18)


### Bug Fixes

* **linting:** no linter run outlives Neovim ([#61](https://github.com/AH-Merii/nvim-config/issues/61)) ([4024169](https://github.com/AH-Merii/nvim-config/commit/40241693b4d9552cb9b0a6ab2d40d115f48d6c5c))

## [0.13.0](https://github.com/AH-Merii/nvim-config/compare/v0.12.0...v0.13.0) (2026-10-18)


### Features

* **ui:** messages and the cmdline come from neoblocks' messages module ([#58](https://github.com/AH-Merii/nvim-config/issues/58)) ([1101292](https://github.com/AH-Merii/nvim-config/commit/11012923a0e985a9f29e1cb03a5d47ad0e936b15))

## [0.12.0](https://github.com/AH-Merii/nvim-config/compare/v0.11.0...v0.12.0) (2026-10-18)


### Bug Fixes

* **lsp:** no process a server started outlives the server or Neovim ([#55](https://github.com/AH-Merii/nvim-config/issues/55)) ([00411e7](https://github.com/AH-Merii/nvim-config/commit/00411e799f139be97a765a875069ef2a9fdb49f5))

## [0.11.0](https://github.com/AH-Merii/nvim-config/compare/v0.10.0...v0.11.0) (2026-10-18)


### Features

* **linting:** entering a buffer lints only when something changed ([#53](https://github.com/AH-Merii/nvim-config/issues/53)) ([3994978](https://github.com/AH-Merii/nvim-config/commit/3994978fa6c4a67572b2fd3ad48dd95fc4bc6f29))

## [0.10.0](https://github.com/AH-Merii/nvim-config/compare/v0.9.0...v0.10.0) (2026-10-18)


### Features

* **app:** install and load plugins with vim.pack, not lazy.nvim ([#50](https://github.com/AH-Merii/nvim-config/issues/50)) ([a275fe7](https://github.com/AH-Merii/nvim-config/commit/a275fe780897047c450e134fde81f40019ae059b))

## [0.9.0](https://github.com/AH-Merii/nvim-config/compare/v0.8.0...v0.9.0) (2026-10-18)


### Features

* .env files get Neovim's own env filetype ([6322fee](https://github.com/AH-Merii/nvim-config/commit/6322fee6f1dc4200ca1fc577777417f2e8bdb7d0))


### Restructuring

* **app:** run startup as six named, timed phases ([d98b40e](https://github.com/AH-Merii/nvim-config/commit/d98b40e045632154e576129841b6f06d9936fbab))

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
