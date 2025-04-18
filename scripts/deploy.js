const { ethers } = require("hardhat");
async function main() {
  // 获取账户
  const signers = await ethers.getSigners();
  const deployer = signers[0];
  console.log("Deploying contracts with account:", deployer.address);
  console.log("deployer balance:", 
  ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");
  /* 获取私钥账户
  const privateKey = "PRIVATE_KEY";
  const deployer = new hre.ethers.Wallet(privateKey, hre.ethers.provider);
  */
  // 获取合约工厂
  const AuctionContract = await ethers.getContractFactory("AuctionContract", { signer: deployer }); //signer：部署的账户
  const BudgetContract = await ethers.getContractFactory("BudgetContract", { signer: deployer });
  const FundContract = await ethers.getContractFactory("FundContract", { signer: deployer });
  const HotelContract = await ethers.getContractFactory("HotelContract", { signer: deployer });
  const ManagementContract = await ethers.getContractFactory("ManagementContract", { signer: deployer });
  /*依赖外部库 libraries
  const Token = await hre.ethers.getContractFactory("Token", {
    libraries: { SafeMath: safeMath.target },
  });*/
  //部署合约
  //拍卖
  const auctionContract = await AuctionContract.deploy();
  await auctionContract.waitForDeployment();
  console.log("AuctionContract deployed to:", auctionContract.target);
  //基金
  const fundContract = await FundContract.deploy();
  await fundContract.waitForDeployment();
  console.log("FundContract deployed to:", fundContract.target);
  //rwa管理
  const platformFeeRate = 100; // 单位：0.01%
  const fundFeeRate = 50; // 单位：0.01%
  const managementContract = await ManagementContract.deploy(platformFeeRate, fundFeeRate, fundContract.target);
  await managementContract.waitForDeployment();
  console.log("ManagementContract deployed to:", managementContract.target);
  const managementContractTx = await fundContract.initialize(managementContract.target);
  await managementContractTx.wait();
  //酒店
  const hotelContract = await HotelContract.deploy(deployer.address, managementContract.target);
  await hotelContract.waitForDeployment();
  console.log("HotelContract deployed to:", hotelContract.target);
  //预算
  const budgetContract = await BudgetContract.deploy(deployer.address, hotelContract.target);
  await budgetContract.waitForDeployment();
  console.log("BudgetContract deployed to:", budgetContract.target);
  const budgetTx = await hotelContract.setBudgetAddress(budgetContract.target);
  await budgetTx.wait(); // 等待交易确认

  
  
  console.log("deployer balance:", 
    ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");
  
  return {
    deployer,
    auctionContract,
    fundContract,
    managementContract,
    hotelContract,
    budgetContract,
    platformFeeRate,
    fundFeeRate
  };
}

if (require.main === module) {
  // 仅在直接运行时执行
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

module.exports = main;