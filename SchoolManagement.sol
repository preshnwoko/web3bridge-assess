// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract SchoolManagement {
    // Access control
    address public owner;
    mapping(address => bool) public isRegistrar;
    mapping(address => bool) public isPayroll;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyRegistrar() {
        require(isRegistrar[msg.sender], "Not registrar");
        _;
    }

    modifier onlyPayroll() {
        require(isPayroll[msg.sender], "Not payroll");
        _;
    }

    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event RegistrarSet(address indexed account, bool allowed);
    event PayrollSet(address indexed account, bool allowed);

    // Reentrancy guard
    uint256 private locked = 1;
    modifier nonReentrant() {
        require(locked == 1, "Reentrant");
        locked = 2;
        _;
        locked = 1;
    }

    // School logic
    enum Level { L100, L200, L300, L400 }

    struct Student {
        uint256 id;
        string name;
        address wallet;
        Level level;

        bool feePaid;
        uint256 feePaidAmount;
        uint64 feePaidAt;

        uint64 registeredAt;
    }

    struct Staff {
        uint256 id;
        string name;
        address wallet;

        uint256 salaryWei;
        uint64 registeredAt;
        uint64 lastPaidAt;
    }

    mapping(Level => uint256) public feeByLevel;

    mapping(uint256 => Student) private students;
    uint256 public studentCount;
    uint256[] private studentIds;

    mapping(uint256 => Staff) private staffs;
    uint256 public staffCount;
    uint256[] private staffIds;

    event StudentRegistered(uint256 indexed id, address indexed wallet, Level level, uint256 fee, uint256 timestamp);
    event StudentFeeMarked(uint256 indexed id, uint256 amount, uint256 timestamp);
    event StaffRegistered(uint256 indexed id, address indexed wallet, uint256 salaryWei, uint256 timestamp);
    event StaffPaid(uint256 indexed id, address indexed wallet, uint256 amount, uint256 timestamp);

    constructor(
        uint256 fee100,
        uint256 fee200,
        uint256 fee300,
        uint256 fee400
    ) {
        owner = msg.sender;

        // owner is registrar + payroll by default
        isRegistrar[msg.sender] = true;
        isPayroll[msg.sender] = true;

        feeByLevel[Level.L100] = fee100;
        feeByLevel[Level.L200] = fee200;
        feeByLevel[Level.L300] = fee300;
        feeByLevel[Level.L400] = fee400;
    }

    // Admin controls
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Bad owner");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function setRegistrar(address account, bool allowed) external onlyOwner {
        isRegistrar[account] = allowed;
        emit RegistrarSet(account, allowed);
    }

    function setPayroll(address account, bool allowed) external onlyOwner {
        isPayroll[account] = allowed;
        emit PayrollSet(account, allowed);
    }

    function setFee(Level level, uint256 newFee) external onlyOwner {
        feeByLevel[level] = newFee;
    }

    // Manual update for offchain payments (keeps your requirement)
    function markStudentPaid(uint256 studentId, uint256 amount, uint64 paidAt) external onlyOwner {
        Student storage s = students[studentId];
        require(s.wallet != address(0), "Student not found");
        require(!s.feePaid, "Already paid");

        s.feePaid = true;
        s.feePaidAmount = amount;
        s.feePaidAt = paidAt;

        emit StudentFeeMarked(studentId, amount, paidAt);
    }

    // Register student (fee on registration)
    function registerStudent(string calldata name, address wallet, Level level)
        external
        payable
        onlyRegistrar
        returns (uint256 id)
    {
        require(wallet != address(0), "Bad wallet");
        uint256 fee = feeByLevel[level];
        require(fee > 0, "Fee not set");
        require(msg.value == fee, "Wrong fee");

        id = ++studentCount;

        students[id] = Student({
            id: id,
            name: name,
            wallet: wallet,
            level: level,
            feePaid: true,
            feePaidAmount: msg.value,
            feePaidAt: uint64(block.timestamp),
            registeredAt: uint64(block.timestamp)
        });

        studentIds.push(id);

        emit StudentRegistered(id, wallet, level, msg.value, block.timestamp);
    }

    // Register staff
    function registerStaff(string calldata name, address wallet, uint256 salaryWei)
        external
        onlyRegistrar
        returns (uint256 id)
    {
        require(wallet != address(0), "Bad wallet");

        id = ++staffCount;
        staffs[id] = Staff({
            id: id,
            name: name,
            wallet: wallet,
            salaryWei: salaryWei,
            registeredAt: uint64(block.timestamp),
            lastPaidAt: 0
        });

        staffIds.push(id);

        emit StaffRegistered(id, wallet, salaryWei, block.timestamp);
    }

    // Pay staff (from contract balance)
    function payStaff(uint256 staffId) external onlyPayroll nonReentrant {
        Staff storage st = staffs[staffId];
        require(st.wallet != address(0), "Staff not found");
        require(st.salaryWei > 0, "Salary not set");
        require(address(this).balance >= st.salaryWei, "Insufficient balance");

        st.lastPaidAt = uint64(block.timestamp);

        (bool ok, ) = st.wallet.call{value: st.salaryWei}("");
        require(ok, "Transfer failed");

        emit StaffPaid(staffId, st.wallet, st.salaryWei, block.timestamp);
    }

    // Getters
    function getStudent(uint256 studentId) external view returns (Student memory) {
        Student memory s = students[studentId];
        require(s.wallet != address(0), "Student not found");
        return s;
    }

    function getAllStudentIds() external view returns (uint256[] memory) {
        return studentIds;
    }

    function getStaff(uint256 staffId) external view returns (Staff memory) {
        Staff memory st = staffs[staffId];
        require(st.wallet != address(0), "Staff not found");
        return st;
    }

    function getAllStaffIds() external view returns (uint256[] memory) {
        return staffIds;
    }

    // Fund the contract for payroll
    receive() external payable {}
}
