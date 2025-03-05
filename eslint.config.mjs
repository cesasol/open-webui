// @ts-check
import js from '@eslint/js';
import svelte from 'eslint-plugin-svelte';
import ts from 'typescript-eslint';
import svelteParser from 'svelte-eslint-parser';
import eslintPluginPrettierRecommended from 'eslint-plugin-prettier/recommended';
import globals from 'globals';
import tsParser from '@typescript-eslint/parser';
export default [
	{
		ignores: [
			'static',
			'node_modules',
			'**/node_modules',
			'test',
			'.svelte-kit',
			'__pycache__',
			'.venv',
			'build',
			'dist'
		]
	},
	{ languageOptions: { globals: { ...globals.browser } } },
	js.configs.recommended,
	...ts.configs.recommended,
	...svelte.configs['flat/all'],
	eslintPluginPrettierRecommended,
	...svelte.configs['flat/prettier'],
	{
		files: [
			'**/*.svelte',
			'*.svelte',
			// Need to specify the file extension for Svelte 5 with rune symbols
			'**/*.svelte.js',
			'*.svelte.js',
			'**/*.svelte.ts',
			'*.svelte.ts'
		],
		rules: {
			'svelte/no-unused-class-name': 0,
			'svelte/block-lang': 0,
			'svelte/experimental-require-strict-events': 0
		},
		languageOptions: { parser: svelteParser, parserOptions: { parser: tsParser } }
	}
];
