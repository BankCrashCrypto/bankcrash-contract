import { ethers, upgrades, run } from "hardhat";
import { config } from "dotenv";

config();

async function main() {
  const BankCrashTokenV1 = await ethers.getContractFactory(
    "BankCrashTokenV1"
  );
  console.log("Deploying BankCrashTokenV1...");

  const contract = await upgrades.deployProxy(BankCrashTokenV1, [], {
    initializer: "initialize",
    kind: "transparent",
  });
  await contract.deployed();
  console.log("BankCrashTokenV1 deployed to:", contract.address);

  const admin = await upgrades.admin.getInstance();
  console.log('Admin is set to -> ', admin.address);

  console.log(`Verifying contract on Etherscan...`);

  await run(`verify:verify`, {
    address: contract.address,
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});