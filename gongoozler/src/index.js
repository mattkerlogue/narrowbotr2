/**
 * Welcome to Cloudflare Workers!
 *
 * This is a template for a Scheduled Worker: a Worker that can run on a
 * configurable interval:
 * https://developers.cloudflare.com/workers/platform/triggers/cron-triggers/
 *
 * - Run `npm run dev` in your terminal to start a development server
 * - Run `curl "http://localhost:8787/__scheduled?cron=*+*+*+*+*"` to see your worker in action
 * - Run `npm run deploy` to publish your worker
 *
 * Learn more at https://developers.cloudflare.com/workers/
 */

import { Octokit } from 'octokit';
import { env } from 'cloudflare:workers';

export default {
	async fetch(request) {
		const octokit = new Octokit({
			auth: env.GITHUB_TOKEN,
		});

		await octokit.request('POST /repos/mattkerlogue/narrowbotr2/actions/workflows/bot.yaml/dispatches', {
			owner: 'mattkerlogue',
			repo: 'narrowbotr2',
			workflow_id: 'bot.yaml',
			ref: 'main',
			headers: {
				'X-GitHub-Api-Version': '2026-03-10',
			},
		});
	},
};
