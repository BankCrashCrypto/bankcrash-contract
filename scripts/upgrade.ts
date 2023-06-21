import { ethers, upgrades, run } from "hardhat";
import { config } from "dotenv";

config();

async function main() {
    const BankCrashTokenV2 = await ethers.getContractFactory(
        "BankCrashTokenV2"
    );
    console.log("Upgrading BankCrashTokenV2...");
    const contract = await upgrades.upgradeProxy(
        "contract-address",
        BankCrashTokenV2
    );

    console.log("BankCrashTokenV2 deployed to:", contract.address);  

    console.log("Upgraded Successfully");

    console.log(`Verifying contract on Etherscan...`);
    await run(`verify:verify`, {
        address: contract.address,
    });
    // *** DISCLAIMER ***
    // ONLY MAKE CONTRACT IMMUTABLE IF THE CONTRACT IS AUDITED AND IT IS BULLETPROOF
    // console.log("Transferring proxy admin ownership to the zero address...");

    // const zeroAddress = '0x0000000000000000000000000000000000000000';
    // const admin = await upgrades.admin.getInstance();
    // await admin.transferProxyAdminOwnership(proxyAddress, zeroAddress);

    // console.log("Transferred Successfully. The contract is now immutable.");
    // *** DISCLAIMER ***
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});