import { privateKeyToAccount } from 'viem/accounts';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { Wallet } from "zksync-ethers";
import { Deployer } from '@matterlabs/hardhat-zksync';
import Web3 from 'web3';
import dotenv from 'dotenv';

dotenv.config();


export default async function (hre: HardhatRuntimeEnvironment) {
  let privateKey = process.env.PRIVATE_KEY as `0x${string}`;
  const deployerWallet = new Wallet(privateKey);
  const deployer = new Deployer(hre, deployerWallet);

  const artifact = await deployer.loadArtifact('DYLIMarketplace');
  
  const tokenContract = await deployer.deploy(artifact);
  const contractAddress = await tokenContract.getAddress();
  console.log(`${artifact.contractName} was deployed to ${contractAddress}`);

  try {
    await hre.run("verify:verify", {
      address: contractAddress
    });
    console.log(`Contract verified at ${contractAddress}`);
  } catch (error) {
    console.error(`Verification failed for ${contractAddress}:`, error);
  }

}