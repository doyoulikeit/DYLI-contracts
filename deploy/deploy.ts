import { Wallet } from "zksync-ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync";

export default async function (hre: HardhatRuntimeEnvironment) {
  const wallet = new Wallet(process.env.PRIVATE_KEY as string);

  const deployer = new Deployer(hre, wallet);

  const artifact = await deployer.loadArtifact("DYLI_new");

  const usdcAddress = "0x75Bf8F439d205B8eE0DE9d3622342eb05985859B";
  const royaltyReceiver = "0x2f2A13462f6d4aF64954ee84641D265932849b64";
  const feeNumerator = 500;
  const uri = "https://www.dyli.io/api/metadata/";

  const tokenContract = await deployer.deploy(artifact, [uri, royaltyReceiver, feeNumerator, usdcAddress]);

  console.log(`${artifact.contractName} was deployed to ${await tokenContract.getAddress()}`);
}
