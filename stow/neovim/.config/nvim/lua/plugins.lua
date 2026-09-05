-- Plugins are installed under vim.fn.stdpath("data"), outside this repository.
require("lazy").setup({
	-- Theme
	{
		"folke/tokyonight.nvim",
		lazy = false,
		priority = 1000,
		config = function()
			vim.cmd.colorscheme("tokyonight-night")
		end,
	},

	-- Statusline
	{
		"nvim-lualine/lualine.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			require("lualine").setup({
				options = { theme = "tokyonight" },
			})
		end,
	},

	-- Icons
	{ "nvim-tree/nvim-web-devicons", lazy = true },

	-- Which-key popup
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		config = function()
			require("which-key").setup({})
		end,
	},

	-- File picker
	{
		"nvim-telescope/telescope.nvim",
		lazy = false,
		dependencies = { "nvim-lua/plenary.nvim" },
	},
	--  treesitter parsing
	{
		"nvim-treesitter/nvim-treesitter",
		lazy = false,
		build = ":TSUpdate",
	},
	-- Markdown
	{
		"MeanderingProgrammer/render-markdown.nvim",
		dependencies = { "nvim-treesitter/nvim-treesitter" },
		opts = {},
	},

	-- LSP
	{
		"neovim/nvim-lspconfig",
		dependencies = {
			"williamboman/mason.nvim",
			"williamboman/mason-lspconfig.nvim",
			"hrsh7th/nvim-cmp",
			"hrsh7th/cmp-nvim-lsp",
			"L3MON4D3/LuaSnip",
		},
		config = function()
			require("mason").setup()
			require("mason-lspconfig").setup({
				ensure_installed = { "basedpyright", "ruff", "gopls", "bashls", "lua_ls", "ts_ls" },
			})

			-- completion
			local cmp = require("cmp")
			cmp.setup({
				snippet = {
					expand = function(args)
						require("luasnip").lsp_expand(args.body)
					end,
				},
				mapping = cmp.mapping.preset.insert({
					["<CR>"] = cmp.mapping.confirm({ select = true }),
					["<Tab>"] = cmp.mapping.select_next_item(),
					["<S-Tab>"] = cmp.mapping.select_prev_item(),
					["<C-Space>"] = cmp.mapping.complete(),
				}),
				sources = { { name = "nvim_lsp" } },
			})

			local capabilities = require("cmp_nvim_lsp").default_capabilities()

			-- keymaps
			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function(args)
					local opts = { buffer = args.buf, silent = true }
					vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
					vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
					vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
					vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
					vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
					vim.keymap.set("n", "<leader>f", function()
						vim.lsp.buf.format({ async = true })
					end, opts)
				end,
			})

			-- ✅ Neovim 0.11+ LSP config (no require("lspconfig"))
			vim.lsp.config("basedpyright", {
				capabilities = capabilities,
				settings = {
					basedpyright = { typeCheckingMode = "basic" },
					python = {
						analysis = {
							autoSearchPaths = true,
							useLibraryCodeForTypes = true,
						},
					},
				},
			})

			vim.lsp.config("ruff", {
				capabilities = capabilities,
				on_attach = function(client, _)
					client.server_capabilities.hoverProvider = false
				end,
			})

			vim.lsp.config("gopls", {
				capabilities = capabilities,
				settings = {
					gopls = { gofumpt = true, staticcheck = true },
				},
			})

			vim.lsp.config("lua_ls", {
				capabilities = capabilities,
				settings = {
					Lua = {
						diagnostics = { globals = { "vim" } },
						telemetry = { enable = false },
					},
				},
			})

			vim.lsp.config("bashls", {
				capabilities = capabilities,
			})

			vim.lsp.config("ts_ls", {
				capabilities = capabilities,
			})

			vim.lsp.enable({ "basedpyright", "ruff", "gopls", "bashls", "lua_ls", "ts_ls" })

			vim.diagnostic.config({
				virtual_text = true,
				severity_sort = true,
				float = { border = "rounded" },
			})
		end,
	},
})
