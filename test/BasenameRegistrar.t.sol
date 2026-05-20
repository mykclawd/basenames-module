// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {BasenameRegistrar} from "../src/BasenameRegistrar.sol";
import {BasenameUtils} from "../src/lib/BasenameUtils.sol";

// ─── Concrete test contract ──────────────────────────────────────────────────

contract TestCounter is BasenameRegistrar {
    address public owner;
    uint256 public treasuryBalance; // tracks ETH held for other purposes

    error NotOwner();
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address owner_)
        BasenameRegistrar(address(0), address(0), address(0))
    {
        owner = owner_;
    }

    function registerBasename(string memory name, uint256 duration)
        external
        payable
        onlyOwner
    {
        _registerBasename(name, duration);
    }

    function setForwardResolution(string memory name) external onlyOwner {
        _setForwardResolution(name);
    }

    /// Simulate contract holding ETH for other purposes (treasury)
    function depositTreasury() external payable {
        treasuryBalance += msg.value;
    }

    receive() external payable override {}
}

// ─── Mock RegistrarController ─────────────────────────────────────────────────

contract MockRegistrarController {
    uint256 public constant PRICE = 0.001 ether;
    bool public registerCalled;
    uint256 public lastValueReceived;
    address public lastOwner;
    string public lastName;

    struct Price {
        uint256 base;
        uint256 premium;
    }

    struct RegisterRequest {
        string name;
        address owner;
        uint256 duration;
        address resolver;
        bytes[] data;
        bool reverseRecord;
        uint256[] coinTypes;
        uint256 referralExpiry;
        bytes referralData;
    }

    function rentPrice(string memory, uint256) external pure returns (Price memory) {
        return Price({base: PRICE, premium: 0});
    }

    function register(RegisterRequest calldata request) external payable {
        require(msg.value >= PRICE, "InsufficientValue");
        registerCalled = true;
        lastValueReceived = msg.value;
        lastOwner = request.owner;
        lastName = request.name;
        // Simulate registrar keeping exact price, contract gets rest back
        // (in reality registrar keeps the ETH; we just don't send it back here)
    }

    function available(string memory) external pure returns (bool) {
        return true;
    }
}

// ─── Mock ReverseRegistrar ────────────────────────────────────────────────────

contract MockReverseRegistrar {
    string public lastSetName;
    address public lastClaimer;

    function setName(string memory name) external returns (bytes32) {
        lastSetName = name;
        lastClaimer = msg.sender;
        return bytes32(0);
    }

    function setNameForAddr(
        address addr,
        address,
        address,
        string memory name
    ) external returns (bytes32) {
        lastSetName = name;
        lastClaimer = addr;
        return bytes32(0);
    }
}

// ─── Mock L2Resolver ─────────────────────────────────────────────────────────

contract MockL2Resolver {
    mapping(bytes32 => address) public addrs;
    mapping(bytes32 => string) public names;

    function setAddr(bytes32 node, address a) external {
        addrs[node] = a;
    }

    function setAddr(bytes32 node, uint256, address a) external {
        addrs[node] = a;
    }

    function addr(bytes32 node) external view returns (address) {
        return addrs[node];
    }

    function setName(bytes32 node, string calldata name) external {
        names[node] = name;
    }
}

// ─── Test contract using mocks ────────────────────────────────────────────────

contract TestCounterWithMocks is BasenameRegistrar {
    address public owner;

    error NotOwner();
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(
        address owner_,
        address controller,
        address reverseRegistrar,
        address resolver
    ) BasenameRegistrar(controller, reverseRegistrar, resolver) {
        owner = owner_;
    }

    function registerBasename(string memory name, uint256 duration)
        external
        payable
        onlyOwner
    {
        _registerBasename(name, duration);
    }

    function setForwardResolution(string memory name) external onlyOwner {
        _setForwardResolution(name);
    }

    receive() external payable override {}
}

// ─── Tests ────────────────────────────────────────────────────────────────────

contract BasenameRegistrarTest is Test {
    MockRegistrarController controller;
    MockReverseRegistrar reverseRegistrar;
    MockL2Resolver resolver;

    address owner = address(0xBEEF);
    address attacker = address(0xBAD);

    function setUp() public {
        controller = new MockRegistrarController();
        reverseRegistrar = new MockReverseRegistrar();
        resolver = new MockL2Resolver();
    }

    function _deploy() internal returns (TestCounterWithMocks) {
        return new TestCounterWithMocks(
            owner,
            address(controller),
            address(reverseRegistrar),
            address(resolver)
        );
    }

    // ── Refund logic ──────────────────────────────────────────────────────────

    /// @dev Sending exact price → no refund, no treasury drain
    function test_noRefundOnExactPayment() public {
        TestCounterWithMocks c = _deploy();
        vm.deal(owner, 1 ether);

        uint256 price = controller.PRICE();
        uint256 ownerBefore = owner.balance;

        vm.prank(owner);
        c.registerBasename{value: price}("mycontract", 365 days);

        // Owner got nothing back (sent exact amount)
        assertEq(owner.balance, ownerBefore - price);
    }

    /// @dev Sending more than price → only excess refunded, not treasury
    function test_onlyExcessRefundedNotTreasury() public {
        TestCounterWithMocks c = _deploy();
        vm.deal(owner, 1 ether);

        // Deposit treasury ETH into the contract
        uint256 treasuryAmount = 0.5 ether;
        vm.deal(address(c), treasuryAmount);

        uint256 price = controller.PRICE();
        uint256 overpay = 0.002 ether; // send 2x the price
        uint256 ownerBefore = owner.balance;
        uint256 contractBefore = address(c).balance;

        vm.prank(owner);
        c.registerBasename{value: overpay}("mycontract", 365 days);

        uint256 expectedRefund = overpay - price;

        // Owner received back only the excess from this call
        assertEq(owner.balance, ownerBefore - overpay + expectedRefund, "wrong refund to owner");

        // Contract lost exactly the price from its balance (the pre-existing treasury is intact)
        // Note: contract started with treasuryAmount, received overpay, paid price to registrar,
        // refunded excess to owner → net change = 0 (treasury untouched)
        assertEq(
            address(c).balance,
            contractBefore + overpay - price - expectedRefund,
            "treasury should be unchanged"
        );
        // Simplifies to: contract balance unchanged
        assertEq(address(c).balance, contractBefore, "treasury was drained");
    }

    /// @dev Treasury ETH must NEVER be used to pay for registration
    function test_treasuryNotUsedForRegistration() public {
        TestCounterWithMocks c = _deploy();
        vm.deal(owner, 1 ether);

        // Fund the contract treasury
        uint256 treasuryAmount = 1 ether;
        vm.deal(address(c), treasuryAmount);

        uint256 price = controller.PRICE();
        uint256 contractBefore = address(c).balance;

        // Send exact price only — no extra
        vm.prank(owner);
        c.registerBasename{value: price}("mycontract", 365 days);

        // Contract balance unchanged — registration used msg.value, not treasury
        assertEq(address(c).balance, contractBefore, "treasury was touched");
    }

    /// @dev Registration with insufficient msg.value reverts with InsufficientETH
    function test_underpaymentReverts() public {
        TestCounterWithMocks c = _deploy();
        vm.deal(owner, 1 ether);

        uint256 price = controller.PRICE();

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BasenameRegistrar.InsufficientETH.selector,
                price,
                price - 1
            )
        );
        c.registerBasename{value: price - 1}("mycontract", 365 days);
    }

    // ── Access control ────────────────────────────────────────────────────────

    /// @dev Non-owner cannot call registerBasename
    function test_nonOwnerCannotRegister() public {
        TestCounterWithMocks c = _deploy();
        vm.deal(attacker, 1 ether);

        vm.prank(attacker);
        vm.expectRevert(TestCounterWithMocks.NotOwner.selector);
        c.registerBasename{value: 0.001 ether}("mycontract", 365 days);
    }

    /// @dev Non-owner cannot call setForwardResolution
    function test_nonOwnerCannotSetForward() public {
        TestCounterWithMocks c = _deploy();

        vm.prank(attacker);
        vm.expectRevert(TestCounterWithMocks.NotOwner.selector);
        c.setForwardResolution("mycontract");
    }

    // ── Input validation ──────────────────────────────────────────────────────

    /// @dev Empty name reverts
    function test_emptyNameReverts() public {
        TestCounterWithMocks c = _deploy();
        vm.deal(owner, 1 ether);

        vm.prank(owner);
        vm.expectRevert(BasenameRegistrar.EmptyName.selector);
        c.registerBasename{value: 0.001 ether}("", 365 days);
    }

    /// @dev Duration below minimum reverts
    function test_shortDurationReverts() public {
        TestCounterWithMocks c = _deploy();
        vm.deal(owner, 1 ether);

        vm.prank(owner);
        vm.expectRevert(BasenameRegistrar.InvalidDuration.selector);
        c.registerBasename{value: 0.001 ether}("mycontract", 364 days);
    }

    // ── Registration correctness ──────────────────────────────────────────────

    /// @dev Registration calls controller with correct params
    function test_registrationCallsController() public {
        TestCounterWithMocks c = _deploy();
        vm.deal(owner, 1 ether);

        vm.prank(owner);
        c.registerBasename{value: 0.001 ether}("mycontract", 365 days);

        assertTrue(controller.registerCalled(), "controller.register not called");
        assertEq(controller.lastOwner(), address(c), "wrong owner");
        assertEq(controller.lastName(), "mycontract", "wrong name");
    }

    /// @dev BasenameRegistered event emitted
    function test_registrationEmitsEvent() public {
        TestCounterWithMocks c = _deploy();
        vm.deal(owner, 1 ether);

        vm.expectEmit(true, true, false, true);
        emit BasenameRegistrar.BasenameRegistered("mycontract", address(c), 365 days);

        vm.prank(owner);
        c.registerBasename{value: 0.001 ether}("mycontract", 365 days);
    }

    // ── Forward resolution ────────────────────────────────────────────────────

    /// @dev setForwardResolution writes correct addr to resolver
    function test_setForwardResolutionWritesCorrectNode() public {
        TestCounterWithMocks c = _deploy();
        vm.deal(owner, 1 ether);

        // Register first
        vm.prank(owner);
        c.registerBasename{value: 0.001 ether}("mycontract", 365 days);

        // Set forward
        vm.prank(owner);
        c.setForwardResolution("mycontract");

        bytes32 node = BasenameUtils.basenameNode("mycontract");
        assertEq(resolver.addr(node), address(c), "forward addr not set");
    }

    /// @dev ForwardResolutionSet event emitted
    function test_forwardResolutionEmitsEvent() public {
        TestCounterWithMocks c = _deploy();
        vm.deal(owner, 1 ether);

        vm.prank(owner);
        c.registerBasename{value: 0.001 ether}("mycontract", 365 days);

        vm.expectEmit(true, true, false, false);
        emit BasenameRegistrar.ForwardResolutionSet("mycontract", address(c));

        vm.prank(owner);
        c.setForwardResolution("mycontract");
    }

    // ── getBasenamePrice ──────────────────────────────────────────────────────

    /// @dev getBasenamePrice returns correct value
    function test_getBasenamePrice() public {
        TestCounterWithMocks c = _deploy();
        uint256 price = c.getBasenamePrice("mycontract", 365 days);
        assertEq(price, controller.PRICE(), "wrong price");
    }

    // ── Exploit: treasury drain attack ───────────────────────────────────────

    /// @dev Attacker front-runs registerBasename, sending 0 ETH, hoping treasury covers cost
    function test_exploit_attackerCannotUseTreasuryToRegister() public {
        TestCounterWithMocks c = _deploy();

        // Treasury holds 10 ETH
        vm.deal(address(c), 10 ether);

        // Attacker (not owner) cannot call registerBasename at all
        vm.deal(attacker, 0.001 ether);
        vm.prank(attacker);
        vm.expectRevert(TestCounterWithMocks.NotOwner.selector);
        c.registerBasename{value: 0.001 ether}("stolenname", 365 days);

        // Treasury is intact
        assertEq(address(c).balance, 10 ether);
    }

    /// @dev Owner calling registerBasename with 0 ETH cannot steal treasury to pay registration
    function test_exploit_ownerCannotDrainTreasuryViaRegistration() public {
        TestCounterWithMocks c = _deploy();
        vm.deal(owner, 0); // owner has no ETH

        // Contract has treasury
        vm.deal(address(c), 10 ether);
        uint256 treasuryBefore = address(c).balance;
        uint256 price = controller.PRICE();

        // Calling with 0 ETH — module rejects before forwarding anything to registrar
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BasenameRegistrar.InsufficientETH.selector,
                price,
                0
            )
        );
        c.registerBasename{value: 0}("mycontract", 365 days);

        // Treasury is completely untouched
        assertEq(address(c).balance, treasuryBefore, "treasury was touched on failed registration");
    }

    /// @dev Excess refund goes to caller, not leaked to contract balance
    function test_excessRefundGoesToCaller() public {
        TestCounterWithMocks c = _deploy();
        vm.deal(owner, 1 ether);

        uint256 price = controller.PRICE();
        uint256 overpay = price + 0.5 ether;
        uint256 ownerBefore = owner.balance;

        vm.prank(owner);
        c.registerBasename{value: overpay}("mycontract", 365 days);

        // Owner got back exactly the excess
        assertEq(owner.balance, ownerBefore - price, "owner should only net the price");
        // Contract balance is 0 (no treasury, excess fully refunded)
        assertEq(address(c).balance, 0, "excess leaked to contract");
    }

    // ── BasenameUtils namehash correctness ────────────────────────────────────

    /// @dev basenameNode("incrementer") matches known on-chain node
    function test_basenameNodeCorrect() public pure {
        bytes32 node = BasenameUtils.basenameNode("incrementer");
        // Verified against on-chain ENS registry for incrementer.base.eth
        assertEq(
            node,
            0xf5f00c5c1220fbe1ae93746da7106fef793a4a2eedcbf97ec43a8e928670d32b,
            "wrong namehash for incrementer.base.eth"
        );
    }

    /// @dev BASE_ETH_NODE constant is correct
    function test_baseEthNodeCorrect() public pure {
        // Verified: keccak256(keccak256(0x0...0 + keccak256("eth")) + keccak256("base"))
        assertEq(
            BasenameUtils.BASE_ETH_NODE,
            0xff1e3c0eb00ec714e34b6114125fbde1dea2f24a72fbf672e7b7fd5690328e10,
            "BASE_ETH_NODE constant is wrong"
        );
    }
}
