// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BudgetContract is Ownable {
    address public admin;

    uint256 public balance;

    address public paymentAddress;

    constructor(
        address initialOwner,
        address _paymentAddress
    ) Ownable(initialOwner) {
        paymentAddress = _paymentAddress;
    }

    //预算扣减事件
    event balanceIncreased(uint256 totalAmount, uint256 amount);

    //预算增加事件
    event balanceDecreased(uint256 amount);

    //增加
    function increaseBudget() public payable onlyOwner {
        //
        balance += msg.value;
        emit balanceIncreased(balance, msg.value);
    }

    //减少
    function decreaseBudget(uint256 amount) public onlyOwner {
        require(balance >= amount, "No deposit to withdraw");

        balance -= amount;

        //资金转出
        payable(msg.sender).transfer(amount);

        emit balanceDecreased(amount);
    }

    //扣减红包优惠
    function deduction(uint256 amount) public  {
        //把钱转给ppaymentAddress

        require(msg.sender == paymentAddress, "not paymentContract");


        require(balance >= amount, "budget not enough");

        balance -= amount;

        payable(paymentAddress).transfer(amount);
    }

    function getBalance() public view returns (uint256) {
        return balance;
    }
}
