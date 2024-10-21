import { Wallet } from "zksync-ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync";

export default async function (hre: HardhatRuntimeEnvironment) {
  const wallet = new Wallet(process.env.PRIVATE_KEY as string);

  const deployer = new Deployer(hre, wallet);

  const artifact = await deployer.loadArtifact("DYLI_new");

  const uri = "https://www.dyli.io/api/metadata/";

  const tokenContract = await deployer.deploy(artifact, [uri]);

  console.log(`${artifact.contractName} was deployed to ${await tokenContract.getAddress()}`);
}
