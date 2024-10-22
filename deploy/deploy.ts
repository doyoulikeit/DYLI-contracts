import { createWalletClient, http, parseEther, encodeFunctionData } from 'viem';
import { eip712WalletActions } from 'viem/zksync';
import { privateKeyToAccount } from 'viem/accounts';
import { abstractTestnet } from 'viem/chains';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { Wallet } from "zksync-ethers";
import { Deployer } from '@matterlabs/hardhat-zksync';
import { createClient } from '@supabase/supabase-js';
import Web3 from 'web3';
import dotenv from 'dotenv';

dotenv.config();

const web3 = new Web3(process.env.RPC_URL);

const MAX_RETRIES = 10;

async function sendWithRetry(walletClient: any, method: string, args: any[], account: any, contractAddress: string, abi: any, retries = 0) {
  try {
    const transactionData = encodeFunctionData({
      abi,
      functionName: method,
      args,
    });

    const txHash = await walletClient.sendTransaction({
      to: contractAddress,
      data: transactionData,
      account,
    });

    return txHash;
  } catch (error: unknown) {
    const err = error as Error;
    if (err.message.includes('rpc method is not whitelisted') && retries < MAX_RETRIES) {
      console.log(`RPC error encountered. Retrying ${retries + 1}/${MAX_RETRIES}...`);
      return sendWithRetry(walletClient, method, args, account, contractAddress, abi, retries + 1);
    } else {
      throw err;
    }
  }
}

const abi = [
  {
    "inputs": [
      { "internalType": "uint256", "name": "maxMint", "type": "uint256" },
      { "internalType": "uint256", "name": "price", "type": "uint256" },
      { "internalType": "bool", "name": "_isOE", "type": "bool" },
      { "internalType": "uint256", "name": "startTimestamp", "type": "uint256" },
      { "internalType": "uint256", "name": "endTimestamp", "type": "uint256" },
      { "internalType": "uint256", "name": "minMint", "type": "uint256" }
    ],
    "name": "ownerCreateDrop",
    "outputs": [
      { "internalType": "uint256", "name": "", "type": "uint256" }
    ],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      { "internalType": "uint256", "name": "tokenId", "type": "uint256" },
      { "internalType": "address", "name": "recipient", "type": "address" },
      { "internalType": "uint256", "name": "amount", "type": "uint256" }
    ],
    "name": "ownerMintToken",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  }
];

const balanceOfBatchAbi = [
  {
    "inputs": [
      { "internalType": "address[]", "name": "accounts", "type": "address[]" },
      { "internalType": "uint256[]", "name": "ids", "type": "uint256[]" }
    ],
    "name": "balanceOfBatch",
    "outputs": [
      { "internalType": "uint256[]", "name": "", "type": "uint256[]" }
    ],
    "stateMutability": "view",
    "type": "function"
  }
];

const contract1155 = '0xEd98897E58E61fFB8a4Cf802C6FCc03977975461';

export default async function (hre: HardhatRuntimeEnvironment) {
  let privateKey = process.env.PRIVATE_KEY as `0x${string}`;
  const account = privateKeyToAccount(privateKey);
  const deployerWallet = new Wallet(privateKey);
  const deployer = new Deployer(hre, deployerWallet);

  const artifact = await deployer.loadArtifact('DYLI_new');
  const uri = 'https://www.dyli.io/api/metadata/';
  const tokenContract = await deployer.deploy(artifact, [uri]);
  const contractAddress = await tokenContract.getAddress();
  console.log(`${artifact.contractName} was deployed to ${contractAddress}`);

  const walletClient = createWalletClient({
    account,
    chain: abstractTestnet,
    transport: http(process.env.RPC_URL),
  }).extend(eip712WalletActions());

  const supabaseUrl = process.env.SUPABASE_URL as string;
  const supabaseServiceKey = process.env.SUPABASE_KEY as string;
  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  const { data: products, error } = await supabase
    .from('products')
    .select('tokenid, price, supply, minimum, created_at, startDate, endDate, dropType')
    .order('tokenid', { ascending: true })

  if (error) {
    console.error('Error fetching products:', error);
    return;
  }

  let currentTokenId = products.length > 0 ? products[0].tokenid - 1 : 0;

  for (const product of products) {
    const supply = product.supply ?? 0;
    const startTimestamp = product.startDate
      ? Math.floor(new Date(product.startDate).getTime() / 1000)
      : Math.floor(new Date(product.created_at).getTime() / 1000);

    while (currentTokenId < product.tokenid - 1) {
      currentTokenId++;
      console.log(`Creating dummy drop for skipped tokenId ${currentTokenId}`);
      await sendWithRetry(
        walletClient,
        'ownerCreateDrop',
        [1, parseEther('0.01'), false, Math.floor(Date.now() / 1000), Math.floor(Date.now() / 1000) + 86400, 1],
        account,
        contractAddress,
        abi
      );
    }

    try {
      const createDropTx = await sendWithRetry(
        walletClient,
        'ownerCreateDrop',
        [
          supply,
          parseEther(product.price.toString()),
          product.dropType === 'OE',
          startTimestamp,
          Math.floor(new Date(product.endDate).getTime() / 1000),
          product.minimum,
        ],
        account,
        contractAddress,
        abi
      );

      console.log(`Creating drop for tokenId ${product.tokenid}: ${createDropTx}`);
      currentTokenId = product.tokenid;
    } catch (error) {
      console.error(`Error creating drop for tokenId ${product.tokenid}:`, error);
    }
  }

  console.log('All drops created.');


  const { data: productsDistinct, error: productsError } = await supabase
    .from('products')
    .select('tokenid')

  if (productsError) {
    console.error('Error fetching tokenIds:', productsError);
    return;
  }

  const tokenIds = productsDistinct.map(product => product.tokenid);

  const { data: users, error: userError } = await supabase
    .from('user_view')
    .select('id, wallet');

  if (userError) {
    console.error('Error fetching users:', userError);
    return;
  }

  const BATCH_SIZE = 20;

  for (const user of users) {
    for (let batchStart = 0; batchStart < tokenIds.length; batchStart += BATCH_SIZE) {
      const batchTokenIds = tokenIds.slice(batchStart, batchStart + BATCH_SIZE);
      const balances = await getBalances(user.wallet, batchTokenIds);
  
      for (let i = 0; i < batchTokenIds.length; i++) {
        const tokenId = batchTokenIds[i];
        const balance = balances[i];
  
        if (balance > 0) {
          try {
            const mintTx = await sendWithRetry(
              walletClient,
              'ownerMintToken',
              [tokenId, user.wallet, balance],
              account,
              contractAddress,
              abi
            );
            console.log(`Minted ${balance} tokens of tokenId ${tokenId} for user ${user.id}: ${mintTx}`);
          } catch (error) {
            console.error(`Error minting tokens for user ${user.id} (tokenId ${tokenId}):`, error);
          }
        }
      }
    }
  }

  console.log('All tokens minted.');
}

async function getBalances(walletAddress: string, tokenIds: number[]): Promise<number[]> {
  const BATCH_SIZE = 20;
  const balances: number[] = [];

  for (let batchStart = 0; batchStart < tokenIds.length; batchStart += BATCH_SIZE) {
    const batchTokenIds = tokenIds.slice(batchStart, batchStart + BATCH_SIZE);
    const accounts = new Array(batchTokenIds.length).fill(walletAddress);

    try {
      const contract = new web3.eth.Contract(balanceOfBatchAbi, contract1155);
      const batchBalances = await contract.methods.balanceOfBatch(accounts, batchTokenIds).call();

      if (!Array.isArray(batchBalances)) {
        throw new Error('Unexpected response format');
      }

      balances.push(...batchBalances.map((balance: any) => parseInt(balance, 10)));
    } catch (error) {
      console.error(`Error fetching balances for wallet ${walletAddress} in batch ${batchStart}:`, error);
      return [];
    }
  }

  return balances;
}