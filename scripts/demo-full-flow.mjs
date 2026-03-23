#!/usr/bin/env node
/**
 * demo-full-flow.mjs — End-to-end ArcHive Marketplace demo
 *
 * Demonstrates the complete task lifecycle using a single wallet
 * acting as BOTH client and agent:
 *   1. Register as agent (if not already)
 *   2. Approve USDC spend + Create a task (hiring yourself)
 *   3. Accept the task
 *   4. Complete the task
 *   5. Approve the task (releases payment)
 *   6. Rate the agent
 *   7. Log a Nanopayment record
 *
 * Usage:  node scripts/demo-full-flow.mjs
 */

import {
  createPublicClient,
  createWalletClient,
  http,
  defineChain,
  parseAbi,
  formatUnits,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

// ── Config ────────────────────────────────────────────────────────────────────
const ARC_RPC   = 'https://rpc.testnet.arc.network';
const PRIV_KEY  = process.env.PRIVATE_KEY || '***REDACTED_TESTNET_KEY***';

const AGENT_REGISTRY    = '0xA94eb06e682Ff599F2Fa4e170E1ECF01C3093059';
const TASK_MANAGER      = '0xcCCaf01E7d2C201D8EDa0f4bC1Cd0B6A778494d9';
const REPUTATION_ENGINE = '0xDa349CFc2eCdE2578f9cf02a3c94125aE6d78c40';
const NANOPAY_DEMO      = '0xE835de690bC570d025399DB7B576B3F422cFA5e7';
const USDC_ADDRESS      = '0x3600000000000000000000000000000000000000';

const TASK_PAYMENT = 500_000n; // 0.5 USDC

// ── Chain ─────────────────────────────────────────────────────────────────────
const arcTestnet = defineChain({
  id: 1637,
  name: 'Arc Testnet',
  nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: [ARC_RPC] } },
});

// ── ABIs ──────────────────────────────────────────────────────────────────────
const registryAbi = parseAbi([
  'function registerAgent(string,string,string,uint256,string[])',
  'function isRegistered(address) view returns (bool)',
  'function getAgent(address) view returns ((string name,string description,string endpoint,uint256 pricePerTask,string[] skillTags,bool active,uint256 registeredAt,uint256 totalTasks,uint256 totalEarned))',
]);

const taskManagerAbi = parseAbi([
  'function createTask(address agent,string description,uint256 payment) returns (uint256 taskId)',
  'function acceptTask(uint256 taskId)',
  'function completeTask(uint256 taskId,string resultHash)',
  'function approveTask(uint256 taskId)',
  'function getTask(uint256 taskId) view returns ((address client,address agent,string description,uint256 payment,string resultHash,uint8 state,uint256 createdAt,uint256 acceptedAt,uint256 completedAt))',
  'function getTaskCount() view returns (uint256)',
  'event TaskCreated(uint256 indexed taskId,address indexed client,address indexed agent,uint256 payment)',
]);

const reputationAbi = parseAbi([
  'function rateAgent(address agent,uint256 taskId,uint8 rating,string comment)',
  'function getReputation(address agent) view returns (uint256 totalTasks,uint256 avgRatingX100,uint256 totalRatings)',
]);

const nanopayAbi = parseAbi([
  'function recordPayment(address agent,uint256 amount,string taskType)',
  'function getPaymentCount() view returns (uint256)',
]);

const erc20Abi = parseAbi([
  'function approve(address spender,uint256 amount) returns (bool)',
  'function balanceOf(address account) view returns (uint256)',
  'function allowance(address owner,address spender) view returns (uint256)',
]);

// ── Helpers ───────────────────────────────────────────────────────────────────
const TASK_STATES = ['Created', 'Accepted', 'Completed', 'Approved', 'Disputed', 'Resolved', 'Cancelled'];

function separator(title) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`  STEP: ${title}`);
  console.log('='.repeat(60));
}

async function sendTx(walletClient, publicClient, params, label) {
  console.log(`  [>] Sending: ${label}...`);
  const hash = await walletClient.writeContract(params);
  console.log(`      Tx: ${hash}`);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  console.log(`      [+] Confirmed in block ${receipt.blockNumber} (${receipt.status})`);
  return receipt;
}

// ── Main ──────────────────────────────────────────────────────────────────────
async function main() {
  console.log('\n' + '#'.repeat(60));
  console.log('#   ArcHive Marketplace — Full Demo Flow');
  console.log('#'.repeat(60));

  const account = privateKeyToAccount(PRIV_KEY);
  console.log(`\n[*] Wallet: ${account.address}`);

  const pub = createPublicClient({ chain: arcTestnet, transport: http() });
  const wal = createWalletClient({ account, chain: arcTestnet, transport: http() });

  // ── 0. Pre-flight checks ───────────────────────────────────────────────────
  separator('Pre-flight checks');

  const balance = await pub.readContract({
    address: USDC_ADDRESS, abi: erc20Abi, functionName: 'balanceOf', args: [account.address],
  });
  console.log(`  USDC balance: ${formatUnits(balance, 6)} USDC`);

  if (balance < TASK_PAYMENT) {
    console.error('  [x] Insufficient USDC balance. Need at least 0.5 USDC.');
    console.error('      Get testnet USDC from the Arc faucet first.');
    process.exit(1);
  }

  // ── 1. Register as agent ────────────────────────────────────────────────────
  separator('1 — Register as Agent');

  const isReg = await pub.readContract({
    address: AGENT_REGISTRY, abi: registryAbi, functionName: 'isRegistered', args: [account.address],
  });

  if (isReg) {
    const ag = await pub.readContract({
      address: AGENT_REGISTRY, abi: registryAbi, functionName: 'getAgent', args: [account.address],
    });
    console.log(`  [i] Already registered as "${ag.name}" — skipping.`);
  } else {
    await sendTx(wal, pub, {
      address: AGENT_REGISTRY,
      abi: registryAbi,
      functionName: 'registerAgent',
      args: [
        'CodeReviewer',
        'Smart contract code review',
        'https://api.archive.demo/code-review',
        1_000_000n,
        ['solidity', 'audit', 'security'],
      ],
    }, 'registerAgent("CodeReviewer")');
  }

  // ── 2. Approve USDC + Create Task ──────────────────────────────────────────
  separator('2 — Approve USDC & Create Task');

  // Check current allowance
  const allowance = await pub.readContract({
    address: USDC_ADDRESS, abi: erc20Abi, functionName: 'allowance',
    args: [account.address, TASK_MANAGER],
  });
  console.log(`  Current allowance: ${formatUnits(allowance, 6)} USDC`);

  if (allowance < TASK_PAYMENT) {
    await sendTx(wal, pub, {
      address: USDC_ADDRESS,
      abi: erc20Abi,
      functionName: 'approve',
      args: [TASK_MANAGER, TASK_PAYMENT * 10n], // approve extra for future use
    }, `approve(TaskManager, ${formatUnits(TASK_PAYMENT * 10n, 6)} USDC)`);
  } else {
    console.log('  [i] Sufficient allowance already set — skipping approve.');
  }

  // Get current task count to predict the new task ID
  const taskCountBefore = await pub.readContract({
    address: TASK_MANAGER, abi: taskManagerAbi, functionName: 'getTaskCount',
  });
  console.log(`  Tasks before: ${taskCountBefore}`);

  // Create task — hiring ourselves
  const createReceipt = await sendTx(wal, pub, {
    address: TASK_MANAGER,
    abi: taskManagerAbi,
    functionName: 'createTask',
    args: [account.address, 'Review the ArcHive Marketplace smart contracts for security vulnerabilities', TASK_PAYMENT],
  }, 'createTask(self, "Review ArcHive contracts", 0.5 USDC)');

  // Derive task ID from count
  const taskId = taskCountBefore; // tasks are 0-indexed
  console.log(`  [+] Created task ID: ${taskId}`);

  // Verify
  const task = await pub.readContract({
    address: TASK_MANAGER, abi: taskManagerAbi, functionName: 'getTask', args: [taskId],
  });
  console.log(`  Task state: ${TASK_STATES[task.state]}`);
  console.log(`  Client: ${task.client}`);
  console.log(`  Agent:  ${task.agent}`);
  console.log(`  Payment: ${formatUnits(task.payment, 6)} USDC`);

  // ── 3. Accept Task ─────────────────────────────────────────────────────────
  separator('3 — Accept Task (as Agent)');

  await sendTx(wal, pub, {
    address: TASK_MANAGER,
    abi: taskManagerAbi,
    functionName: 'acceptTask',
    args: [taskId],
  }, `acceptTask(${taskId})`);

  const afterAccept = await pub.readContract({
    address: TASK_MANAGER, abi: taskManagerAbi, functionName: 'getTask', args: [taskId],
  });
  console.log(`  Task state: ${TASK_STATES[afterAccept.state]}`);

  // ── 4. Complete Task ────────────────────────────────────────────────────────
  separator('4 — Complete Task (submit result)');

  const resultHash = 'QmDemo1234567890abcdef_audit_report_v1';
  await sendTx(wal, pub, {
    address: TASK_MANAGER,
    abi: taskManagerAbi,
    functionName: 'completeTask',
    args: [taskId, resultHash],
  }, `completeTask(${taskId}, "${resultHash}")`);

  const afterComplete = await pub.readContract({
    address: TASK_MANAGER, abi: taskManagerAbi, functionName: 'getTask', args: [taskId],
  });
  console.log(`  Task state: ${TASK_STATES[afterComplete.state]}`);
  console.log(`  Result hash: ${afterComplete.resultHash}`);

  // ── 5. Approve Task (release payment) ───────────────────────────────────────
  separator('5 — Approve Task (release payment)');

  const balanceBefore = await pub.readContract({
    address: USDC_ADDRESS, abi: erc20Abi, functionName: 'balanceOf', args: [account.address],
  });

  await sendTx(wal, pub, {
    address: TASK_MANAGER,
    abi: taskManagerAbi,
    functionName: 'approveTask',
    args: [taskId],
  }, `approveTask(${taskId})`);

  const balanceAfter = await pub.readContract({
    address: USDC_ADDRESS, abi: erc20Abi, functionName: 'balanceOf', args: [account.address],
  });

  const afterApprove = await pub.readContract({
    address: TASK_MANAGER, abi: taskManagerAbi, functionName: 'getTask', args: [taskId],
  });
  console.log(`  Task state: ${TASK_STATES[afterApprove.state]}`);
  console.log(`  USDC before: ${formatUnits(balanceBefore, 6)}`);
  console.log(`  USDC after:  ${formatUnits(balanceAfter, 6)}`);
  console.log(`  Payment transferred: ${formatUnits(balanceAfter - balanceBefore, 6)} USDC`);

  // ── 6. Rate the Agent ───────────────────────────────────────────────────────
  separator('6 — Rate Agent');

  const rateAbi = [{ name: 'rateAgent', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'taskId', type: 'uint256' }, { name: 'rating', type: 'uint8' }, { name: 'comment', type: 'string' }], outputs: [] }];
  await sendTx(wal, pub, {
    address: TASK_MANAGER,
    abi: rateAbi,
    functionName: 'rateAgent',
    args: [taskId, 5, 'Excellent audit, found critical vulnerability in reentrancy guard!'],
  }, `rateAgent(task ${taskId}, 5 stars)`);

  const rep = await pub.readContract({
    address: REPUTATION_ENGINE, abi: reputationAbi, functionName: 'getReputation', args: [account.address],
  });
  console.log(`  Reputation:`);
  console.log(`    Total tasks rated: ${rep.totalRatings}`);
  console.log(`    Avg rating: ${Number(rep.avgRatingX100) / 100}/5`);

  // ── 7. Log Nanopayment ──────────────────────────────────────────────────────
  separator('7 — Record Nanopayment');

  await sendTx(wal, pub, {
    address: NANOPAY_DEMO,
    abi: nanopayAbi,
    functionName: 'recordPayment',
    args: [account.address, TASK_PAYMENT, 'code-review'],
  }, `recordPayment(self, ${formatUnits(TASK_PAYMENT, 6)} USDC, "code-review")`);

  const payCount = await pub.readContract({
    address: NANOPAY_DEMO, abi: nanopayAbi, functionName: 'getPaymentCount',
  });
  console.log(`  Total nanopay records: ${payCount}`);

  // ── Done ────────────────────────────────────────────────────────────────────
  console.log('\n' + '#'.repeat(60));
  console.log('#   Demo Complete!');
  console.log('#'.repeat(60));
  console.log(`\n  Task ${taskId} went through the full lifecycle:`);
  console.log('    Created -> Accepted -> Completed -> Approved');
  console.log('    + Agent rated 5/5');
  console.log('    + Nanopayment recorded');
  console.log(`\n  Run "node scripts/check-status.mjs" to inspect marketplace state.\n`);
}

main().catch((err) => {
  console.error('\n[x] Fatal error:', err.shortMessage || err.message);
  if (err.cause) console.error('    Cause:', err.cause.shortMessage || err.cause.message || err.cause);
  process.exit(1);
});
