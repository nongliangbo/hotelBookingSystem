// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "hardhat/console.sol";

import "./ManagementContract.sol";
import "./BudgetContract.sol";

contract HotelContract is Ownable, EIP712 {
    using ECDSA for bytes32;

    bytes32 private constant MESSAGE_TYPEHASH =
        keccak256(
            "VoucherSignedMessage(address user,address roomAddress,uint256 voucherId,uint256 voucherValue)"
        );

    //EIP712 用于签名
    constructor(
        address owner,
        address _managementAddress
    ) Ownable(owner) EIP712("HotelBookingSystem", "1") {
        managementAddress = _managementAddress;
    }

    struct VoucherSignedMessage {
        address user;
        address roomAddress;
        uint256 voucherId;
        uint256 voucherValue;
    }

    address managementAddress;
    address budgetAddress;

    enum BookingStatus {
        booked,
        canceled,
        settled
    }

    struct Room {
        uint256 roomId;
        address roomAddress; // 对应的 HouseToken 合约地址
        string descriptionURL; // 房间描述的URL
        string imagesURL; // 房间图片的URL
        uint256 price; // 每晚的价格
        uint256 next30daysBooking; // 未来30天的可用性（0 表示可用，1 表示已预订）
        uint256 lastBookingUpdate; // 上次预订信息更新时间戳
        bool isAvailable; // 是否可预订
    }

    struct Booking {
        uint256 bookingId; // 预订的唯一标识
        uint256 roomId; // 房间的唯一标识
        address user; // 下单用户地址
        uint256 checkInTime; // 计划入住时间（时间戳）
        uint256 checkOutTime; // 计划退房时间（时间戳）
        uint256 voucherId; // 使用的优惠券ID（如未使用，则为0）
        uint256 voucherValue; // 优惠券折扣的金额
        BookingStatus status;
    }

    struct Comment {
        uint256 commmentId; // 评论ID
        address user; // 用户地址
        uint256 roomId;
        string contentHash; // 评论内容哈希
        uint8 rating; //评分
        bool isDdeleted; // 是否删除
    }

    uint256 roomCount = 0;
    mapping(uint256 => Room) public rooms;
    uint256 bookingCount = 0;
    mapping(uint256 => Booking) public bookings;
    mapping(address => uint256) public blance; //记录用户的余额
    mapping(uint256 => Comment) public comments; //记录用户的评论
    mapping(address => bool) public isListed;

    uint256 constant CHECK_IN_HOUR = 14; // 入住时间 14:00，用于计算逻辑日
    uint256 constant SECONDS_PER_DAY = 86400; //每天秒数

    event roomListed(uint256 roomId);
    event roomUpdated(
        uint256 roomId,
        string _descriptionURL,
        string _imagesURL,
        uint256 _price
    );
    event roomUnlisted(uint256 roomId);
    event BookingCreated(
        uint256 bookingId,
        address user,
        uint256 roomId,
        uint256 checkInTime,
        uint256 checkOutTime,
        uint256 discountAmount
    );
    event BookingFailed(address user, uint256 roomId, string reason);
    event BookingCanceled(
        uint256 bookingId,
        address canceledBy,
        uint256 refundAmount
    );
    event BookingSettled(uint256 bookingId, uint256 amount);
    event Deposited(address user, uint256 amount);
    event Withdrawed(address user, uint256 amount);

    function setBudgetAddress(address _budgetAddress) external onlyOwner {
        budgetAddress = _budgetAddress;
    }

    function getRooms() external view returns (Room[] memory) {
        Room[] memory roomArray = new Room[](roomCount);
        for (uint256 i = 0; i < roomCount; i++) {
            roomArray[i] = rooms[i + 1];
        }
        return roomArray;
    }

    function listRoom(
        address _roomAddress,
        string memory _descriptionURL,
        string memory _imagesURL,
        uint256 _price
    ) external onlyOwner {
        //判断房屋是否合法
        require(
            ManagementContract(payable(managementAddress)).isValidHouse(
                _roomAddress
            ),
            "invalid room"
        );
        //判断是否重复上架
        require(!isListed[_roomAddress], "Room is already listed");
        rooms[roomCount] = Room({
            roomId: roomCount,
            roomAddress: _roomAddress,
            descriptionURL: _descriptionURL,
            imagesURL: _imagesURL, 
            price: _price,
            next30daysBooking: 0,
            lastBookingUpdate: block.timestamp,
            isAvailable: true
        });
        isListed[_roomAddress] = true;
        roomCount++;
        emit roomListed(roomCount);
    }

    function updateRoom(
        uint256 roomId,
        string memory _descriptionURL,
        string memory _imagesURL,
        uint256 _price,
        uint256 _next30daysBooking
    ) external onlyOwner {
        // 确保房间存在
        require(roomId > 0 && roomId <= roomCount, "Room does not exist");
        Room storage room = rooms[roomId];
        // 更新房间信息
        room.descriptionURL = _descriptionURL;
        room.imagesURL = _imagesURL;
        room.price = _price;
        room.next30daysBooking = _next30daysBooking;
        room.lastBookingUpdate = block.timestamp; // 更新修改时间
        emit roomUpdated(roomId, _descriptionURL, _imagesURL, _price);
    }

    function unlistRoom(uint256 roomId) external onlyOwner {
        // 确保房间存在
        require(roomId > 0 && roomId <= roomCount, "Room does not exist");
        Room storage room = rooms[roomId];
        // 下架房间
        room.isAvailable = false;
        emit roomUnlisted(roomId);
    }

    // 计算逻辑日期（基于 14:00 的调整时间戳）
    function getLogicalDate(uint256 timestamp) internal pure returns (uint256) {
        uint256 dayTimestamp = timestamp % SECONDS_PER_DAY; //今天的时间戳
        uint256 daysSinceEpoch = timestamp / SECONDS_PER_DAY; //自1970年到现在经过天数
        if (dayTimestamp < CHECK_IN_HOUR * 3600) {
            return daysSinceEpoch - 1; // 计算为前一天
        }
        return daysSinceEpoch; // 计算为当天
    }

    function createBooking(
        uint256 _roomId,
        uint256 _checkInTime,
        uint256 _checkOutTime,
        uint256 _voucherId,
        uint256 _voucherValue,
        bytes calldata signature
    ) external {
        //判断房间是否存在
        require(_roomId >= 0 && _roomId <= roomCount, "Room does not exist");
        //判断入住时间
        require(
            _checkInTime < _checkOutTime,
            "Check-in must be before check-out"
        );
        require(_checkInTime > block.timestamp, "Check-in must be after now");

        Room storage room = rooms[_roomId];

        //计算逻辑日
        uint256 logicalCheckIn = getLogicalDate(_checkInTime);
        uint256 logicalCheckOut = getLogicalDate(_checkOutTime);
        //上次更新经过天数
        uint256 daysPassed = getLogicalDate(block.timestamp) -
            getLogicalDate(room.lastBookingUpdate);
        // 经过天数位移
        if (daysPassed > 0) {
            room.next30daysBooking >>= daysPassed;
        }

        // 计算入住天数的位掩码
        uint256 checkInOffset = logicalCheckIn -
            getLogicalDate(block.timestamp);
        uint256 checkOutOffset = logicalCheckOut -
            getLogicalDate(block.timestamp);
        uint256 mask = ((1 << (checkOutOffset - checkInOffset)) - 1) <<
            checkInOffset;

        //验证入住时间
        if ((room.next30daysBooking & mask) != 0) {
            emit BookingFailed(
                msg.sender,
                _roomId,
                "Room not available for selected dates"
            );
            return;
        }

        uint256 discountAmount = 0;
        console.log("before singature check");
        // 验证优惠券签名
        // 签名内容 address user,address roomAddress,uint256 voucherId,uint256 voucherValue
        if (signature.length != 0) {
            console.log("singature check");
            bytes32 structHash = keccak256(
                abi.encode(
                    MESSAGE_TYPEHASH,
                    msg.sender,
                    room.roomAddress,
                    _voucherId,
                    _voucherValue
                )
            );
            bytes32 digest = _hashTypedDataV4(structHash);
            //解析签名，验证签名者必须为owner
            require(
                digest.recover(signature) == owner(),
                "Invalid voucher signature"
            );
            discountAmount = _voucherValue;
        }
        console.log("after singature check");

        require(
            blance[msg.sender] + discountAmount >
                room.price * (logicalCheckOut - logicalCheckIn + 1),
            "not enough blance"
        );

        blance[msg.sender] -=
            room.price *
            (logicalCheckOut - logicalCheckIn + 1) +
            discountAmount;

        //从预算合约获取优惠金额
        if(discountAmount > 0){
            require(budgetAddress != address(0), "Budget contract not set");
            BudgetContract(budgetAddress).deduction(discountAmount);            
        }

        //预订成功。更新next30days
        room.next30daysBooking |= mask;
        room.lastBookingUpdate = block.timestamp;

        //创建订单
        bookings[bookingCount] = Booking({
            bookingId: bookingCount,
            roomId: _roomId,
            user: msg.sender,
            checkInTime: _checkInTime,
            checkOutTime: _checkOutTime,
            voucherId: _voucherId,
            voucherValue: discountAmount,
            status: BookingStatus.booked
        });
        bookingCount++;

        emit BookingCreated(
            bookingCount,
            msg.sender,
            _roomId,
            _checkInTime,
            _checkOutTime,
            discountAmount
        );
    }

    function cancelBooking(uint256 bookingId) external {
        // 验证预订ID有效性
        require(
            bookingId >= 0 && bookingId <= bookingCount,
            "Invalid booking ID"
        );
        Booking storage booking = bookings[bookingId];

        // 验证预订状态和调用者权限
        require(
            booking.status == BookingStatus.booked,
            "Booking is not active"
        );
        require(
            msg.sender == booking.user || msg.sender == owner(),
            "Only booking user or owner can cancel"
        );

        Room storage room = rooms[booking.roomId];

        // 计算入住天数的逻辑日
        uint256 logicalCheckIn = getLogicalDate(booking.checkInTime);
        uint256 logicalCheckOut = getLogicalDate(booking.checkOutTime);

        // 计算入住天数的位掩码（与createBooking中相同逻辑）
        uint256 checkInOffset = logicalCheckIn -
            getLogicalDate(room.lastBookingUpdate);
        uint256 checkOutOffset = logicalCheckOut -
            getLogicalDate(room.lastBookingUpdate);
        uint256 mask = ((1 << (checkOutOffset - checkInOffset)) - 1) <<
            checkInOffset;

        // 更新房间可用性：清除预订占用的位
        room.next30daysBooking &= ~mask;
        room.lastBookingUpdate = block.timestamp;

        // 计算应退款金额（总价 - 优惠券金额）
        uint256 totalNights = logicalCheckOut - logicalCheckIn + 1;
        uint256 refundAmount = room.price * totalNights - booking.voucherValue;

        // 更新预订状态
        booking.status = BookingStatus.canceled;

        // 退款给用户
        blance[msg.sender] += refundAmount;

        // 如果使用了优惠券，需要将优惠券金额退回预算合约
        if (booking.voucherValue > 0) {
            (bool success, ) = budgetAddress.call{value: booking.voucherValue}(
                ""
            );
            require(success, "Refund to budget failed");
        }

        // 触发事件
        emit BookingCanceled(bookingId, msg.sender, refundAmount);
    }

    //结算订单
    function settle(uint256 bookingId) public onlyOwner {
        Booking storage booking = bookings[bookingId];
        // 检查订单是否符合结算条件
        require(
            booking.status == BookingStatus.booked,
            "Booking is not active"
        );
        require(
            block.timestamp >= booking.checkOutTime,
            "Booking has not expired"
        );

        // 将订单状态标记为已结算
        booking.status = BookingStatus.settled;
        // 计算应付金额 (总价)
        uint256 logicalCheckIn = getLogicalDate(booking.checkInTime);
        uint256 logicalCheckOut = getLogicalDate(booking.checkOutTime);
        uint256 totalNights = logicalCheckOut - logicalCheckIn + 1;
        uint256 paymentAmount = rooms[booking.roomId].price * totalNights;

        // 将资金转给RWA平台
        ManagementContract(payable(managementAddress)).receiveRevenue{
            value: paymentAmount
        }(rooms[booking.roomId].roomAddress);

        emit BookingSettled(booking.bookingId, paymentAmount);
    }

    //强制结算订单，用于测试
    function forceSettle(uint256 bookingId) external onlyOwner {
        Booking storage booking = bookings[bookingId];
        // 检查订单是否符合结算条件
        require(
            booking.status == BookingStatus.booked,
            "Booking is not active"
        );

        // 将订单状态标记为已结算
        booking.status = BookingStatus.settled;
        // 计算应付金额 (总价)
        uint256 logicalCheckIn = getLogicalDate(booking.checkInTime);
        uint256 logicalCheckOut = getLogicalDate(booking.checkOutTime);
        uint256 totalNights = logicalCheckOut - logicalCheckIn + 1;
        uint256 paymentAmount = rooms[booking.roomId].price * totalNights;

        // 将资金转给RWA平台
        ManagementContract(payable(managementAddress)).receiveRevenue{
            value: paymentAmount
        }(rooms[booking.roomId].roomAddress);

        emit BookingSettled(booking.bookingId, paymentAmount);
    }

    // 结算所有符合条件的订单
    function settleAllEligibleBookings() external onlyOwner {
        for (uint256 i = 1; i <= bookingCount; i++) {
            Booking storage booking = bookings[i];
            if (
                booking.status == BookingStatus.booked &&
                booking.checkOutTime <= block.timestamp
            ) {
                settle(i);
            }
        }
    }

    // 获取符合结算条件的订单数量
    function getEligibleBookingsCount() external view returns (uint256) {
        uint256 eligibleCount = 0;
        for (uint256 i = 1; i <= bookingCount; i++) {
            Booking storage booking = bookings[i];
            if (
                booking.status == BookingStatus.booked &&
                booking.checkOutTime <= block.timestamp
            ) {
                eligibleCount++;
            }
        }
        return eligibleCount;
    }

    //添加评论
    function addComment(
        string calldata contentHash,
        uint8 rating,
        uint256 bookingId
    ) public {
        //bookingId校验
        require(bookingId < bookingCount, "Booking does not exist");
        //判断用户有没有预定
        require(
            bookings[bookingId].user == msg.sender,
            "You are not the guest of this booking"
        );

        Booking storage booking = bookings[bookingId];

        //写评论
        uint256 commentId = uint32(block.timestamp); //使用当前时间戳作为评论ID
        comments[commentId] = Comment({
            commmentId: commentId,
            user: msg.sender,
            roomId: booking.roomId,
            contentHash: contentHash,
            rating: rating,
            isDdeleted: false
        });
    }

    function deleteComment(uint256 commentId) public {
        require(
            comments[commentId].user == msg.sender,
            "Only the comment author can delete their comment."
        );
        comments[commentId].isDdeleted = true;
    }

    //充值余额
    function deposit() public payable {
        require(msg.value > 0, "Deposit amount must be greater than 0");
        blance[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    //提取余额
    function withdraw(uint256 amount) public {
        require(amount <= blance[msg.sender], "Insufficient balance");
        blance[msg.sender] -= amount;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdrawal failed");
        emit Withdrawed(msg.sender, amount);
    }

    receive() external payable {}
}
