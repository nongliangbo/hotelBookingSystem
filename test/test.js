// test/DeployScript.test.js
const { expect } = require("chai");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ethers } = require("hardhat");

//虚拟机环境时间增加
async function increaseTime(seconds) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine");
}

//设置下个block提交的时间
async function setNextBlockTime(timestamp) {
  await ethers.provider.send("evm_setNextBlockTimestamp", [timestamp]);
  await ethers.provider.send("evm_mine");
}

//获取当前block时间
async function getBlockTime() {
  const latestBlock = await ethers.provider.getBlock("latest");
  return latestBlock.timestamp;
}

describe("部署共通部分", function () {
  let userA, userB;
  async function commonFixture() {
    const deploy = require("../scripts/deploy.js");
    try {
      //调用部署脚本
      const contracts = await deploy();
      const signers = await ethers.getSigners();
      userA = signers[1]; //引出账户，用于拍卖
      userB = signers[2]; //引出账户，用于订房
      return contracts;
    } catch (error) {
      throw new Error(`Deployment script failed: ${error.message}`);
    }
  }

  it("检查部署结果", async function () {
    const { deployer, auctionContract, fundContract, managementContract, hotelContract, budgetContract } = await loadFixture(commonFixture);
    expect(deployer).to.exist;
    expect(auctionContract.target).to.be.properAddress;
    expect(fundContract.target).to.be.properAddress;
    expect(managementContract.target).to.be.properAddress;
    expect(hotelContract.target).to.be.properAddress;
    expect(budgetContract.target).to.be.properAddress;
  });

  it("添加房屋", async function () {
    const { deployer, auctionContract, fundContract, managementContract, hotelContract, budgetContract } = await loadFixture(commonFixture);
    const houseName = "Test Token";
    const houseSymbol = "TT";
    const houseDescription = "house for test";
    const totalShares = 100;
    //模拟执行，返回函数返回值
    const houseAddress = await managementContract.createHouse.staticCall(houseName, houseSymbol, houseDescription, totalShares);
    //实际执行，返回tx
    await managementContract.createHouse(houseName, houseSymbol, houseDescription, totalShares);
    //console.log("houseAddress:" , houseAddress);
    const HouseToken = await ethers.getContractFactory("HouseToken");
    const houseToken = HouseToken.attach(houseAddress);
    //验证新建的合约属性
    expect(await houseToken.name()).to.equal(houseName);
    expect(await houseToken.symbol()).to.equal(houseSymbol);
    expect(await houseToken.description()).to.equal(houseDescription);
    expect(await houseToken.totalSupply()).to.equal(totalShares);
    expect(await houseToken.management()).to.equal(managementContract.target);
    expect(await houseToken.balanceOf(managementContract.target)).to.equal(totalShares);
  });

  it("创建拍卖", async function () {
    const { deployer, auctionContract, fundContract, managementContract, hotelContract, budgetContract } = await loadFixture(commonFixture);
    //创建房屋
    const houseAddress = await managementContract.createHouse.staticCall("Test Token", "TT", "house for test", 100);
    await managementContract.connect(deployer).createHouse("Test Token", "TT", "house for test", 100);
    //创建拍卖
    await managementContract.connect(deployer).auctionHouse(houseAddress, auctionContract, 100, ethers.parseEther("1"), 86400);
    expect(await auctionContract.auctionCount()).to.equal(1);
  });

  it("竞拍", async function () {
    const { deployer, auctionContract, fundContract, managementContract, hotelContract, budgetContract } = await loadFixture(commonFixture);
    //创建房屋
    const houseAddress = await managementContract.createHouse.staticCall("Test Token", "TT", "house for test", 100);
    await managementContract.connect(deployer).createHouse("Test Token", "TT", "house for test", 100);
    //创建拍卖
    await managementContract.connect(deployer).auctionHouse(houseAddress, auctionContract, 100, ethers.parseEther("1"), 86400);
    //console.log("time: ", await getBlockTime());
    //console.log("ayctions: ", await auctionContract.auctions(0));
    await increaseTime(86301);
    await auctionContract.connect(userA).placeBid(0, { value: ethers.parseEther("1.9") });

  });

  it("拍卖结算", async function () {
    const { deployer, auctionContract, fundContract, managementContract, hotelContract, budgetContract } = await loadFixture(commonFixture);
    //创建房屋
    const houseAddress = await managementContract.createHouse.staticCall("Test Token", "TT", "house for test", 100);
    await managementContract.connect(deployer).createHouse("Test Token", "TT", "house for test", 100);
    //创建拍卖
    await managementContract.connect(deployer).auctionHouse(houseAddress, auctionContract, 100, ethers.parseEther("1"), 86400);
    await increaseTime(86301);
    await auctionContract.connect(userA).placeBid(0, { value: ethers.parseEther("1.9") });
    await increaseTime(100);
    await auctionContract.connect(deployer).finalizeAuction(0);
  });

  it("上架酒店房屋", async function () {
    const { deployer, auctionContract, fundContract, managementContract, hotelContract, budgetContract } = await loadFixture(commonFixture);
    //创建房屋
    const houseAddress = await managementContract.createHouse.staticCall("Test Token", "TT", "house for test", 100);
    await managementContract.connect(deployer).createHouse("Test Token", "TT", "house for test", 100);
    //上架
    await hotelContract.connect(deployer).listRoom(houseAddress, "url1", "url2", 1000);
  });

  it("创建订单", async function () {
    const { deployer, auctionContract, fundContract, managementContract, hotelContract, budgetContract } = await loadFixture(commonFixture);
    //创建房屋
    const houseAddress = await managementContract.createHouse.staticCall("Test Token", "TT", "house for test", 100);
    await managementContract.connect(deployer).createHouse("Test Token", "TT", "house for test", 100);
    //上架
    await hotelContract.connect(deployer).listRoom(houseAddress, "url1", "url2", 1000);
    const timestamp = await getBlockTime();
    //用户先充值
    await hotelContract.connect(userB).deposit({ value: ethers.parseEther("1.9") });
    await hotelContract.connect(userB).createBooking(0, timestamp + 86400, timestamp + 86400 * 3, 0, 0, new Uint8Array(0));
  });

  it("取消订单", async function () {
    const { deployer, auctionContract, fundContract, managementContract, hotelContract, budgetContract } = await loadFixture(commonFixture);
    //创建房屋
    const houseAddress = await managementContract.createHouse.staticCall("Test Token", "TT", "house for test", 100);
    await managementContract.connect(deployer).createHouse("Test Token", "TT", "house for test", 100);
    //上架
    await hotelContract.connect(deployer).listRoom(houseAddress, "url1", "url2", 1000);
    const timestamp = await getBlockTime();
    await hotelContract.connect(userB).deposit({ value: ethers.parseEther("1.9") });
    await hotelContract.connect(userB).createBooking(0, timestamp + 86400, timestamp + 86400 * 3, 0, 0, "0x");
    hotelContract.connect(userB).cancelBooking(0);    
  });

  it("结算订单", async function () {
    const { deployer, auctionContract, fundContract, managementContract, hotelContract, budgetContract } = await loadFixture(commonFixture);
    //创建房屋
    const houseAddress = await managementContract.createHouse.staticCall("Test Token", "TT", "house for test", 100);
    await managementContract.connect(deployer).createHouse("Test Token", "TT", "house for test", 100);
    console.log("managementContract balance:", 
      ethers.formatEther(await ethers.provider.getBalance(managementContract.target)), "ETH");
    //上架
    await hotelContract.connect(deployer).listRoom(houseAddress, "url1", "url2", ethers.parseEther("2"));
    const timestamp = await getBlockTime();
    await hotelContract.connect(userB).deposit({ value: ethers.parseEther("10") });
    await hotelContract.connect(userB).createBooking(0, timestamp + 86400, timestamp + 86400 * 3, 0, 0, new Uint8Array(0));
    await increaseTime(86401 * 5);
    await hotelContract.connect(deployer).settle(0);
    console.log("fundContract balance:", 
      ethers.formatEther(await ethers.provider.getBalance(fundContract.target)), "ETH");
    console.log("managementContract balance:", 
      ethers.formatEther(await ethers.provider.getBalance(managementContract.target)), "ETH");   
    console.log("userB balance:", 

      ethers.formatEther(await hotelContract.blance(userB.address)), "ETH");   
  });

  it("提取分红", async function () {
    const { deployer, auctionContract, fundContract, managementContract, hotelContract, budgetContract } = await loadFixture(commonFixture);
    //创建房屋
    const houseAddress = await managementContract.createHouse.staticCall("Test Token", "TT", "house for test", 100);
    await managementContract.connect(deployer).createHouse("Test Token", "TT", "house for test", 100);
    console.log("managementContract balance:", 
      ethers.formatEther(await ethers.provider.getBalance(managementContract.target)), "ETH");
    //创建拍卖
    await managementContract.connect(deployer).auctionHouse(houseAddress, auctionContract, 100, ethers.parseEther("1"), 86400);
    expect(await auctionContract.auctionCount()).to.equal(1);    
    //用户A竞拍
    await increaseTime(86300);
    await auctionContract.connect(userA).placeBid(0, { value: ethers.parseEther("2") });
    //拍卖结算
    await increaseTime(200);
    await auctionContract.connect(deployer).finalizeAuction(0);
    //上架
    await hotelContract.connect(deployer).listRoom(houseAddress, "url1", "url2", ethers.parseEther("2"));
    //创建订单
    const timestamp = await getBlockTime();
    await hotelContract.connect(userB).deposit({ value: ethers.parseEther("10") });
    await hotelContract.connect(userB).createBooking(0, timestamp + 86400, timestamp + 86400 * 3, 0, 0, new Uint8Array(0));
    //结算订单
    await increaseTime(86401 * 5);
    await hotelContract.connect(deployer).settle(0);
    console.log("fundContract balance:", 
      ethers.formatEther(await ethers.provider.getBalance(fundContract.target)), "ETH");
    console.log("managementContract balance:", 
      ethers.formatEther(await ethers.provider.getBalance(managementContract.target)), "ETH");   
    console.log("userB balance:", 
      ethers.formatEther(await hotelContract.blance(userB.address)), "ETH");
    //提取分红
    const HouseToken = await ethers.getContractFactory("HouseToken");
    const houseTokenObject = HouseToken.attach(houseAddress);
    await houseTokenObject.connect(userA).withdrawDividends();
    console.log("userA balance:", 
      ethers.formatEther(await ethers.provider.getBalance(userA.address)), "ETH");
  });

  it("模拟优惠券使用", async function () {
    
  });
});