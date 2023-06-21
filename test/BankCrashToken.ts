import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

const MONTHS_IN_SECONDS = 30 * 24 * 60 * 60;

describe("BankCrashToken", function () {
  async function deployBankCrashTokenFixture() {
    let owner: SignerWithAddress;
    let address1: SignerWithAddress;
    let address2: SignerWithAddress;
    
    [owner, address1, address2] = await ethers.getSigners();
    
    // Deploy our contract
    const BankCrashTokenV1 = await ethers.getContractFactory("BankCrashTokenV1");
    const bankCrashToken = await upgrades.deployProxy(BankCrashTokenV1, [], {
      initializer: "initialize",
      kind: "transparent",
    });
    await bankCrashToken.deployed();

    let balanceOwner = await bankCrashToken.balanceOf(owner.address);
    let balanceAddr1 = await bankCrashToken.balanceOf(address1.address);
    let balanceAddr2 = await bankCrashToken.balanceOf(address2.address);
    
    console.log("\n*--------INITIAL BALANCES--------*");
    console.log("Owner's balance -> ", balanceOwner);
    console.log("address1 of balance -> ", balanceAddr1);
    console.log("address2 of balance -> ", balanceAddr2);
    console.log("*---------------------------------*\n");

    return {bankCrashToken, owner, address1, address2}
  }

  async function deployBankCrashTokenWithAddressesFixture() {
    const { bankCrashToken, owner, address1, address2 } = await loadFixture(deployBankCrashTokenFixture);

    // Token transfers
    await bankCrashToken.connect(owner).transfer(address1.address, 1000);
    await bankCrashToken.connect(owner).transfer(address2.address, 1000);
    await bankCrashToken.connect(owner).approve(address1.address, 1000);
    await bankCrashToken.connect(owner).approve(address2.address, 1000);
    
    let balanceOwner = await bankCrashToken.balanceOf(owner.address);
    let balanceAddr1 = await bankCrashToken.balanceOf(address1.address);
    let balanceAddr2 = await bankCrashToken.balanceOf(address2.address);
    
    // console.log("\n*--------INITIAL BALANCES--------*");
    // console.log("Owner's balance -> ", balanceOwner);
    // console.log("address1 of balance -> ", balanceAddr1);
    // console.log("address2 of balance -> ", balanceAddr2);
    // console.log("*---------------------------------*\n");

    return {bankCrashToken, owner, address1, address2}
  }

  async function deployBankCrashTokenWithEventsFixture() {
    const { bankCrashToken, owner, address1, address2 } = await loadFixture(deployBankCrashTokenWithAddressesFixture);
    
    await bankCrashToken.connect(owner).updateBankCrashEvents(true, false, false);
    await bankCrashToken.connect(owner).updateBankCrashEvents(false, true, false);
    await bankCrashToken.connect(owner).updateBankCrashEvents(false, false, true);
    await bankCrashToken.connect(owner).updateBankCrashEvents(true, true, true);

    return {bankCrashToken, owner, address1, address2}
  }
  async function deployBankCrashTokenWithStakesFixture() {
    const { bankCrashToken, owner, address1, address2 } = await loadFixture(deployBankCrashTokenWithAddressesFixture);
    
    await bankCrashToken.connect(address1).approve(bankCrashToken.address, 1000);
    await bankCrashToken.connect(address1).stake(1000, 12);
    await bankCrashToken.connect(address2).approve(bankCrashToken.address, 1000);
    await bankCrashToken.connect(address2).stake(1000, 12);

    let balanceOwner = await bankCrashToken.balanceOf(owner.address);
    let balanceAddr1 = await bankCrashToken.balanceOf(address1.address);
    let balanceAddr2 = await bankCrashToken.balanceOf(address2.address);
    
    // console.log("\n*--------Balance & stakes--------*");
    // console.log("Owner's balance -> ", balanceOwner);
    // console.log("address1 of balance -> ", balanceAddr1);
    // console.log("address2 of balance -> ", balanceAddr2);
    // console.log("address1's stake amount -> ", (await bankCrashToken.stakes(address1.address, 0)).amount);
    // console.log("address2's stake amount -> ", (await bankCrashToken.stakes(address2.address, 0)).amount);
    // console.log("*---------------------------------*\n");

    return {bankCrashToken, owner, address1, address2}
  }

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      const { bankCrashToken, owner } = await loadFixture(deployBankCrashTokenFixture);
      expect(await bankCrashToken.owner()).to.equal(owner.address);
    });

    it("Should be able to transfer tokens from owner to address1", async function () {
      const { bankCrashToken, owner, address1 } = await loadFixture(deployBankCrashTokenFixture);

      const initialOwnerBalance = await bankCrashToken.balanceOf(owner.address);

      await bankCrashToken.connect(owner).transfer(address1.address, ethers.utils.parseEther('100'));
      await bankCrashToken.connect(owner).approve(address1.address, ethers.utils.parseEther('100'));
      const finalOwnerBalance = await bankCrashToken.balanceOf(owner.address);
      expect(initialOwnerBalance.sub(finalOwnerBalance)).to.equal(ethers.utils.parseEther('100'));

      const addr1Balance = await bankCrashToken.balanceOf(address1.address);
      expect(addr1Balance).to.equal(ethers.utils.parseEther('100'));
    });
  });


  describe("Staking", function () {
    it("Should allow users to stake tokens", async function () {
      const { bankCrashToken, address1 } = await loadFixture(deployBankCrashTokenWithAddressesFixture);
      const amountToStake = 1000;

      // Approve the contract to spend tokens on behalf of address1
      await bankCrashToken.connect(address1).approve(bankCrashToken.address, amountToStake);

      // Now address1 should be able to stake
      await bankCrashToken.connect(address1).stake(amountToStake, 6);

      const stake = await bankCrashToken.stakes(address1.address, 0);
      expect(stake.amount).to.equal(amountToStake);
    });
    
    it("Should fail when users try to stake for less than 3 months", async function () {
      const { bankCrashToken, address1 } = await loadFixture(deployBankCrashTokenWithAddressesFixture);
      await expect(bankCrashToken.connect(address1).stake(100, 0)).to.be.revertedWith("Staking period must be at least 3 months");
      await expect(bankCrashToken.connect(address1).stake(100, 1)).to.be.revertedWith("Staking period must be at least 3 months");
      await expect(bankCrashToken.connect(address1).stake(100, 2)).to.be.revertedWith("Staking period must be at least 3 months");
    });
    
    it("Should fail when users try to stake zero tokens", async function () {
      const { bankCrashToken, address1 } = await loadFixture(deployBankCrashTokenWithAddressesFixture);
      await expect(bankCrashToken.connect(address1).stake(0, 6)).to.be.revertedWith("Staking amount must be greater than zero");
    });

    it("Should emit StakeCreated event when staking was succesful", async function () {
      const { bankCrashToken, address1 } = await loadFixture(deployBankCrashTokenWithAddressesFixture);
      const amountToStake = 1000;

      // Approve the contract to spend tokens on behalf of address1
      await bankCrashToken.connect(address1).approve(bankCrashToken.address, amountToStake);

      await expect(bankCrashToken.connect(address1).stake(amountToStake, 6)).to.emit(bankCrashToken, "StakeCreated");
    });
  });

  describe("Unstaking", function () {
    it("Should allow users to unstake tokens", async function () {
      const { bankCrashToken, address1 } = await loadFixture(deployBankCrashTokenWithStakesFixture);
      
      const balanceAfterStake = await bankCrashToken.balanceOf(address1.address);

      await bankCrashToken.connect(address1).unstake(0);

      const balanceAfterUnStake = await bankCrashToken.balanceOf(address1.address);
      const stake = await bankCrashToken.stakes(address1.address, 0);
      expect(balanceAfterUnStake).to.be.above(balanceAfterStake);
      expect(stake.closedAt).to.not.equal(0);
    });

    it("Should apply penalty when user unstakes before 3 months", async function () {
      const { bankCrashToken, address1 } = await loadFixture(deployBankCrashTokenWithStakesFixture);
      const stake = await bankCrashToken.stakes(address1.address, 0);

      const now = await time.latest();
      const totalStakingDuration = stake.endAt.toNumber() - stake.createdAt.toNumber();
      var completedStakingDuration = (stake.endAt.toNumber() - stake.createdAt.toNumber()) * 0.1;
 
      if (completedStakingDuration > totalStakingDuration) {
        completedStakingDuration = totalStakingDuration;
      }

      // 6 months passes
      await time.increaseTo(now + completedStakingDuration);

      await bankCrashToken.connect(address1).unstake(0);
      
      // P (principal)
      // r (annual interest rate)
      // n (compounding frequency)
      // t (time in years)
      const P = stake.amount.toNumber();
      const r = stake.baseAPY.toNumber() / 100;
      const n = 365 * 24 * 60 * 60;
      const t = completedStakingDuration / (365 * 24 * 60 * 60);
      const reward = P * (1 + r / n) ** (n * t);

      const addr1Balance = (await bankCrashToken.balanceOf(address1.address)).toNumber();

      const penaltyFactor = 0.33;
      expect(addr1Balance).to.be.below(reward * penaltyFactor * 1.02);
      expect(addr1Balance).to.be.above(reward * penaltyFactor * 0.98);
    });

    it("Should reward user when he unstakes after at least 3 months", async function () {
      const { bankCrashToken, address1 } = await loadFixture(deployBankCrashTokenWithStakesFixture);
      const stake = await bankCrashToken.stakes(address1.address, 0);

      const now = await time.latest();
      const totalStakingDuration = stake.endAt.toNumber() - stake.createdAt.toNumber();
      var completedStakingDuration = (stake.endAt.toNumber() - stake.createdAt.toNumber()) * 0.7;
 
      if (completedStakingDuration > totalStakingDuration) {
        completedStakingDuration = totalStakingDuration;
      }

      // 6 months passes
      await time.increaseTo(now + completedStakingDuration);

      await bankCrashToken.connect(address1).unstake(0);
      
      // P (principal)
      // r (annual interest rate)
      // n (compounding frequency)
      // t (time in years)
      const P = stake.amount.toNumber();
      const r = stake.baseAPY.toNumber() / 100;
      const n = 365 * 24 * 60 * 60;
      const t = completedStakingDuration / (365 * 24 * 60 * 60);
      const reward = P * (1 + r / n) ** (n * t);

      const addr1Balance = (await bankCrashToken.balanceOf(address1.address)).toNumber();

      const penaltyFactor = 0.33 + 0.67 * completedStakingDuration / totalStakingDuration;
      expect(addr1Balance).to.be.below(reward * penaltyFactor * 1.02);
      expect(addr1Balance).to.be.above(reward * penaltyFactor * 0.98);
    });

    it("Should fail when users try to unstake non-existing stakes", async function () {
      const { bankCrashToken, address1 } = await loadFixture(deployBankCrashTokenWithAddressesFixture);
      await expect(bankCrashToken.connect(address1).unstake(9999)).to.be.revertedWith("This stake does not exist");
    });

    it("Should fail when user wants to unstake twice the same stake", async function () {
      const { bankCrashToken, address1 } = await loadFixture(deployBankCrashTokenWithStakesFixture);
      
      await bankCrashToken.connect(address1).unstake(0);

      await expect(bankCrashToken.connect(address1).unstake(0)).to.be.revertedWith("This stake has already been unstaked");
    });

    it("Should emit StakeRemoved event when unstaking was succesful", async function () {
      const { bankCrashToken, address1 } = await loadFixture(deployBankCrashTokenWithStakesFixture);
      
      await expect(bankCrashToken.connect(address1).unstake(0)).to.emit(bankCrashToken, "StakeRemoved");
    });
  });

  describe("BankCrash events", function () {
    it("Should initalize the corresponding bankcrash events", async function () {
      const { bankCrashToken, owner, address1 } = await loadFixture(deployBankCrashTokenWithEventsFixture);
      
      const numOfBigCrashes = (await bankCrashToken.bankCrashEvents()).bigCrash.toNumber();
      const numOfMediumCrashes = (await bankCrashToken.bankCrashEvents()).mediumCrash.toNumber();
      const numOfSmallCrashes = (await bankCrashToken.bankCrashEvents()).smallCrash.toNumber();

      expect(numOfBigCrashes).to.equal(2);
      expect(numOfMediumCrashes).to.equal(2);
      expect(numOfSmallCrashes).to.equal(2);
    });

    it("Should emit BankCrashEventAdded event when bank crash events were updated", async function () {
      const { bankCrashToken, owner} = await loadFixture(deployBankCrashTokenWithEventsFixture);
      
      await expect(bankCrashToken.connect(owner).updateBankCrashEvents(true, true, true)).to.emit(bankCrashToken, "BankCrashEventAdded");
    });

    it("Should fail when not the owner wants to update bankcrashevents", async function () {
      const { bankCrashToken, address1 } = await loadFixture(deployBankCrashTokenWithEventsFixture);

      await expect(bankCrashToken.connect(address1).updateBankCrashEvents(true, true, true)).to.be.revertedWith("Ownable: caller is not the owner");
    });
      
    it("Should fail when owner tries to call with 0 events", async function () {
        const { bankCrashToken, owner, address1} = await loadFixture(deployBankCrashTokenWithEventsFixture);
        
        await expect(bankCrashToken.connect(owner).updateBankCrashEvents(false, false, false)).to.be.revertedWith("At least one bank crash event should be true");
    });

    it("Should calculate bonusAPY correctly v1", async function () {
      const { bankCrashToken, address1} = await loadFixture(deployBankCrashTokenWithStakesFixture);

      const address1Token = bankCrashToken.connect(address1.address);
      const stake = await bankCrashToken.stakes(address1.address, 0);

      expect(await address1Token.getBonusAPY(stake)).to.equal(0);
    });

    it("Should calculate bonusAPY correctly v2", async function () {
      const { bankCrashToken, owner, address1} = await loadFixture(deployBankCrashTokenWithStakesFixture);

      const address1Token = bankCrashToken.connect(address1.address);
      const stake = await bankCrashToken.stakes(address1.address, 0);

      await bankCrashToken.connect(owner).updateBankCrashEvents(true, true, true);
      expect((await address1Token.getBonusAPY(stake)).toNumber()).to.equal(42 + 14 + 2);
    });

  });
});
