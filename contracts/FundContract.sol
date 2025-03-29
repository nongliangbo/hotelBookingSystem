// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract FundContract is Ownable {
    uint256 public fundBalance;
    address public management;

    event FundsDeposited(address indexed from, uint256 amount);
    event FundsWithdrawn(address indexed to, uint256 amount);
    event ManagementUpdated(address newManagement);

    constructor() Ownable(msg.sender) {}

    // 初始化函数（可由工厂合约调用）
    function initialize(address _management) external onlyOwner {
        require(_management != address(0), "Invalid management address");
        management = _management;
        emit ManagementUpdated(_management);
    }

    // 接收来自管理合约的基金抽成（仅管理合约可调用）
    function receiveRevenueShare() external payable {
        require(
            msg.sender == management,
            "Only management can deposit revenue"
        );
        fundBalance += msg.value;
        emit FundsDeposited(msg.sender, msg.value);
    }

    // 注入资金到基金（ payable 函数，可接收ETH）
    function deposit() external payable {
        require(msg.value > 0, "Amount must be greater than 0");
        fundBalance += msg.value;
        emit FundsDeposited(msg.sender, msg.value);
    }

    // 从基金中提取资金（仅owner可调用）
    function withdraw(uint256 amount) external onlyOwner {
        require(amount <= fundBalance, "Insufficient fund balance");
        fundBalance -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdrawal failed");

        emit FundsWithdrawn(msg.sender, amount);
    }

    // 更新管理合约地址（仅owner可调用）
    function setManagement(address _management) external onlyOwner {
        require(_management != address(0), "Invalid management address");
        management = _management;
        emit ManagementUpdated(_management);
    }

    // 允许合约接收ETH（备用）
    receive() external payable {
        fundBalance += msg.value;
        emit FundsDeposited(msg.sender, msg.value);
    }
}
