// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./HouseToken.sol";
import "./AuctionContract.sol";

contract ManagementContract is Ownable {
    uint256 public platformFeeRate; // 单位: 0.01%
    uint256 public fundFeeRate; // 单位: 0.01%
    uint256 public houseCount;
    mapping(uint256 => address) public houses;
    //基金地址
    address public fundContract;
    
    //事件
    event HouseCreated(uint256 indexed houseId, address houseAddress);
    event RevenueReceived(address indexed houseAddress, uint256 amount, uint256 platformFee, uint256 fundFee);
    event PlatformFeeRateUpdated(uint256 newRate);
    event FundFeeRateUpdated(uint256 newRate);
    event FeeWithdrawn(address recipient, uint256 amount);

    constructor(uint256 _platformFeeRate, uint256 _fundFeeRate, address _fundContract) Ownable(msg.sender) {
        platformFeeRate = _platformFeeRate;
        fundFeeRate = _fundFeeRate;
        fundContract = _fundContract;
    }

    //创建新的erc20/房屋
    //TODO 代理模式创建
    function createHouse(
        string memory houseName,
        string memory houseSymbol,
        string memory houseDescription,
        uint256 totalShares
    ) external onlyOwner returns (address) {
        
        HouseToken newHouse = new HouseToken(
            houseName,
            houseSymbol,
            houseDescription,
            totalShares,
            address(this)
        );
        
        uint256 houseId = houseCount++;
        houses[houseId] = address(newHouse);
        
        emit HouseCreated(houseId, address(newHouse));
        return address(newHouse);
    }

    //判断是否平台创建的房屋合约
    function isValidHouse(address houseAddress) public view returns (bool) {
        for (uint i = 0; i < houseCount; i++) {
            if (houses[i] == houseAddress) {
                return true;
            }
        }
        return false;
    }

    //拍卖
    function auctionHouse(address houseAddress, address auctionAddress, uint256 _tokenAmount, uint256 _minBid, uint256 _duration) external onlyOwner {
        require(isValidHouse(houseAddress), "Not a registered house");
        require(auctionAddress != address(0), "Invalid auction address");
        ERC20(houseAddress).approve(auctionAddress, _tokenAmount);
        AuctionContract(auctionAddress).startAuction(houseAddress, _tokenAmount, _minBid, _duration);
    }

    //从酒店平台接收房租 gas由调用者（管理员）支付
    function receiveRevenue(address houseAddress) external payable {
        require(msg.value > 0, "No revenue received");
        require(isValidHouse(houseAddress), "Not a registered house"); 

        
        // 计算手续费
        uint256 platformFee = (msg.value * platformFeeRate) / 10000;
        uint256 fundFee = (msg.value * fundFeeRate) / 10000;
        uint256 remainingAmount = msg.value - platformFee - fundFee;
        
        // 转账基金维护费
        (bool fundSuccess, ) = fundContract.call{value: fundFee}("");
        require(fundSuccess, "Fund fee transfer failed");
        
        // 将剩余金额转入房屋合约
        (bool houseSuccess, ) = houseAddress.call{value: remainingAmount}("");
        require(houseSuccess, "House revenue transfer failed");
        
        // 通知房屋合约更新分红
        HouseToken(payable(houseAddress)).receiveRevenue(remainingAmount);
        
        emit RevenueReceived(houseAddress, msg.value, platformFee, fundFee);
    }

    function setPlatformFeeRate(uint256 newFeeRate) external onlyOwner {
        require(newFeeRate <= 10000, "Fee rate too high"); // 最大100%
        platformFeeRate = newFeeRate;
        emit PlatformFeeRateUpdated(newFeeRate);
    }

    function setFundFeeRate(uint256 newFeeRate) external onlyOwner {
        require(newFeeRate <= 10000, "Fee rate too high"); // 最大100%
        fundFeeRate = newFeeRate;
        emit FundFeeRateUpdated(newFeeRate);
    }

    //提钱
    function withdraw(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient balance");
        (bool success, ) = owner().call{value: amount}("");
        require(success, "Withdrawal failed");
        emit FeeWithdrawn(owner(), amount);
    }


    function getAllHouses() external view returns (address[] memory) {
        address[] memory houseArray = new address[](houseCount);
        
        for (uint256 i = 0; i < houseCount; i++) {
            houseArray[i] = houses[i];
        }
        
        return houseArray;
    }

    //用于接收ETH
    receive() external payable { }
}