pragma solidity ^0.8.28;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";


contract HotelContract is Ownable, EIP712 {

    using ECDSA for bytes32;

    bytes32 private constant MESSAGE_TYPEHASH = keccak256("VoucherSignedMessage(address user,address roomAddress,uint256 voucherId,uint256 voucherValue)");

    constructor(address owner, address _managementAddress) Ownable(owner) EIP712("HotelBookingSystem", "1"){
        managementAddress = _managementAddress;
    }

    struct VoucherSignedMessage {
        address user;
        address roomAddress;
        uint256 voucherId;
        uint256 voucherValue;
    }

    address managementAddress;

    enum BookingStatus{
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
        uint256 bookingId;       // 预订的唯一标识
        uint256 roomId;          // 房间的唯一标识
        address user;            // 下单用户地址
        address roomAddress;     // 房间的合约地址（对应哪处房产）
        uint256 checkInTime;     // 计划入住时间（时间戳）
        uint256 checkOutTime;    // 计划退房时间（时间戳）
        uint256 voucherId;       // 使用的优惠券ID（如未使用，则为0）
        uint256 voucherValue;    // 优惠券折扣的金额
        BookingStatus status;
    }

    uint256 roomCount = 0;
    Room[] rooms;
    uint256 bookingCount = 0;
    Booking[] bookings;
    mapping (address => uint256) blance;

    uint256 constant CHECK_IN_HOUR = 14; // 入住时间 14:00，用于计算逻辑日
    uint256 constant SECONDS_PER_DAY = 86400; //每天秒数

    event roomListed(uint256 roomId);
    event roomUpdated(uint256 roomId, string _descriptionURL, string _imagesURL, uint256 _price);
    event roomUnlisted(uint256 roomId);
    event BookingCreated(uint256 bookingId, address user, address roomAddress, uint256 checkInTime, uint256 checkOutTime, uint256 discountAmount);
    event BookingFailed(address user, address roomAddress, string reason);

    function getRooms() external view returns (Room[] memory) {
        return rooms;
    }

    function listRoom(
        address _roomAddress,
        string memory _descriptionURL,
        string memory _imagesURL,
        uint256 _price
    ) external onlyOwner{
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
        roomCount++;
    }

    function updateRoom(
        uint256 roomId,
        string memory _descriptionURL,
        string memory _imagesURL,
        uint256 _price,
        uint256 _next30daysBooking
    ) external onlyOwner{
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

    function unlistRoom(uint256 roomId) external onlyOwner{
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
        address _roomAddress,
        uint256 _checkInTime,
        uint256 _checkOutTime,
        uint256 _voucherId, 
        uint256 _voucherValue,
        bytes calldata signature
    ) external{
        require(_roomAddress != address(0), "Invalid room address");
        require(_checkInTime < _checkOutTime, "Check-in must be before check-out");
        require(_checkInTime > block.timestamp, "Check-in must be after now");

        Room storage room = rooms[_roomId];
        
        //计算逻辑日
        uint256 logicalCheckIn = getLogicalDate(_checkInTime);
        uint256 logicalCheckOut = getLogicalDate(_checkOutTime);
        //上次更新经过天数
        uint256 daysPassed = getLogicalDate(block.timestamp) - getLogicalDate(room.lastBookingUpdate);
        // 经过天数位移
        if (daysPassed > 0) {
            room.next30daysBooking >>= daysPassed;
        }

        // 计算入住天数的位掩码
        uint256 checkInOffset = logicalCheckIn - getLogicalDate(block.timestamp);
        uint256 checkOutOffset = logicalCheckOut - getLogicalDate(block.timestamp);
        uint256 mask = ((1 << (checkOutOffset - checkInOffset)) - 1) << checkInOffset;

        //验证入住时间
        if ((room.next30daysBooking & mask) != 0) {
            emit BookingFailed(msg.sender, _roomAddress, "Room not available for selected dates");
            return;
        }

        uint256 discountAmount = 0;
        // 验证优惠券签名
        if (signature.length != 0) {
            bytes32 structHash = keccak256(abi.encode(MESSAGE_TYPEHASH, msg.sender, _roomAddress, _voucherId, _voucherValue));
            bytes32 digest = _hashTypedDataV4(structHash);
            require(digest.recover(signature) == owner(), "Invalid voucher signature");
            discountAmount = _voucherValue;
        }

        require(blance[msg.sender] + discountAmount > room.price * (logicalCheckOut - logicalCheckIn + 1), "not enough blance");

        blance[msg.sender] -= room.price * (logicalCheckOut - logicalCheckIn + 1) + discountAmount;

        //预订成功。更新next30days
        room.next30daysBooking |= mask;
        room.lastBookingUpdate = block.timestamp;

        //创建订单
        bookings[bookingCount] = Booking({
            bookingId: bookingCount,
            roomId: _roomId,
            user: msg.sender,
            roomAddress: _roomAddress,
            checkInTime: _checkInTime,
            checkOutTime: _checkOutTime,
            voucherId: _voucherId,
            voucherValue: discountAmount,
            status: BookingStatus.booked
        });

        emit BookingCreated(bookingCount, msg.sender, _roomAddress, _checkInTime, _checkOutTime, discountAmount);
    }

    function cancelBooking() external{

    }
}
