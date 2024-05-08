// SPDX-License-Identifier: MIT
//import "./lptoken.sol";
//import "./IERC20.sol";
//import "./IERC20.sol";
import "./lptoken.sol";

//import "./IWETH.sol";

pragma solidity ^0.8.17;

contract AMM {
//全局变量


    uint constant ONE_ETH = 10 ** 18;
    mapping(address => address) public pairCreator;//lpAddr pairCreator
    address [] public lpTokenAddressList;//lptoken的数组
    mapping(address => mapping(address => uint)) reserve;//第一个address是lptoken的address ，第2个是相应token的资产，uint是资产的amount

    //检索lptoken
    mapping(address => mapping(address => address)) findLpToken;
    //IWETH immutable WETH;
    //address immutable WETHAddr;

    //borrow slot
    mapping (address => mapping (address => uint)) findBorrowedAmount; // lpaddr tokenaddr amount
    mapping (address =>mapping (address => mapping (address => uint))) findUserBorrowedAmount;//user lpaddr tokenAddr amount




    constructor()
    {
        //WETH = IWETH(_wethAddr);
        //WETHAddr = _wethAddr;
    }

    receive() payable external {}

    modifier reEntrancyMutex() {
        bool _reEntrancyMutex;

        require(!_reEntrancyMutex,"FUCK");
        _reEntrancyMutex = true;
        _;
        _reEntrancyMutex = false;

    }

//业务合约
    //添加流动性

    // function addLiquidityWithETH(address _token, uint _tokenAmount) public payable reEntrancyMutex
    // {
    //     uint ETHAmount = msg.value;
    //     address user = msg.sender;
    //    // address addr = address(this);
    //     WETH.depositETH{value : ETHAmount}();
    //     //WETH.approve(user,ETHAmount);
    //     WETH.transfer(user,ETHAmount);
    //     addLiquidity(WETHAddr,_token, ETHAmount,_tokenAmount);

    // }



    function addLiquidity(address _token0, address _token1, uint _amount0,uint _amount1) public returns (uint shares) {
        
        Lp lptoken;//lptoken接口，为了mint 和 burn lptoken
        
        require(_amount0 > 0 ,"require _amount0 > 0 && _amount1 >0");
        require(_token0 != _token1, "_token0 == _token1");
        IERC20 token0 = IERC20(_token0);
        IERC20 token1 = IERC20(_token1);
        token0.transferFrom(msg.sender, address(this), _amount0);
        token1.transferFrom(msg.sender, address(this), _amount1);
        address lptokenAddr;
        //force cal amount1
        if (findLpToken[_token1][_token0] != address(0)) {
            lptokenAddr = findLpToken[_token1][_token0];
            _amount1 = reserve[lptokenAddr][_token1] * _amount0 / reserve[lptokenAddr][_token0];
        }

        if (findLpToken[_token1][_token0] == address(0)) {
            //当lptoken = 0时，创建lptoken
            shares = _sqrt(_amount0 * _amount1);
            createPair(_token0,_token1);
            lptokenAddr = findLpToken[_token1][_token0];
            
            lptoken = Lp(lptokenAddr);//获取lptoken地址

            
            pairCreator[lptokenAddr] = msg.sender;

            
            
        } else {
            lptoken = Lp(lptokenAddr);//获取lptoken地址
            shares = _min(
                (_amount0 * lptoken.totalSupply()) / reserve[lptokenAddr][_token0],
                (_amount1 * lptoken.totalSupply()) / reserve[lptokenAddr][_token1]
            );
            //获取lptoken地址
        }
        require(shares > 0, "shares = 0");
        //require(1== 0, "3");
        lptoken.mint(msg.sender,shares);

        
        

        _update(lptokenAddr,_token0, _token1, reserve[lptokenAddr][_token0] + _amount0, reserve[lptokenAddr][_token1] + _amount1);
    }
    //移除流动性

    function removeLiquidity(
        address _token0,
        address _token1,
        uint _shares
    ) external returns (uint amount0, uint amount1) {
        Lp lptoken;//lptoken接口，为了mint 和 burn lptoken
        IERC20 token0 = IERC20(_token0);
        IERC20 token1 = IERC20(_token1);
        address lptokenAddr = findLpToken[_token0][_token1];

        lptoken = Lp(lptokenAddr);

        if(pairCreator[lptokenAddr] == msg.sender)
        {
            require(lptoken.balanceOf(msg.sender) - _shares > 1 ,"paieCreator should left 100 wei lptoken in pool");
        }

        amount0 = (_shares * reserve[lptokenAddr][_token0]) / lptoken.totalSupply();//share * totalsuply/bal0
        amount1 = (_shares * reserve[lptokenAddr][_token1]) / lptoken.totalSupply();
        require(amount0 > 0 && amount1 > 0, "amount0 or amount1 = 0");

        lptoken.burn(msg.sender, _shares);
        _update(lptokenAddr,_token0, _token1, reserve[lptokenAddr][_token0] - amount0, reserve[lptokenAddr][_token1] - amount1);
        

        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);
    }

    //交易

    // function swapWithETH(address _tokenOut,uint _disirSli) public payable reEntrancyMutex
    // {
    //     uint amountIn = msg.value;
    //     WETH.depositETH{value : amountIn}();
    //     swapByLimitSli(WETHAddr,_tokenOut,amountIn, _disirSli);
    // }


    // function swapToETH(address _tokenIn, uint _amountIn, uint _disirSli)public {
    //     uint amountOut = swapByLimitSli(_tokenIn,WETHAddr,_amountIn, _disirSli);
    //     WETH.withdrawETH(amountOut);
    //     address payable user = payable(msg.sender);
    //     user.transfer(amountOut);

    // }


    function swap(address _tokenIn, address _tokenOut, uint _amountIn) public returns (uint amountOut) {
        require(
            findLpToken[_tokenIn][_tokenOut] != address(0),
            "invalid token"
        );
        require(_amountIn > 0, "amount in = 0");
        require(_tokenIn != _tokenOut);
        require(_amountIn >= 1000, "require amountIn >= 1000 wei token");

        //variable

        IERC20 tokenIn = IERC20(_tokenIn);
        IERC20 tokenOut = IERC20(_tokenOut);
        address lptokenAddr = findLpToken[_tokenIn][_tokenOut];
        uint reserveIn = reserve[lptokenAddr][_tokenIn];
        uint reserveOut = reserve[lptokenAddr][_tokenOut];

        //swap logic

        tokenIn.transferFrom(msg.sender, address(this), _amountIn);


        uint amountInWithFee = (_amountIn * 997) / 1000;
        amountOut = (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);
        tokenOut.transfer(msg.sender, amountOut);

        //update data
        uint totalReserve0 = reserve[lptokenAddr][_tokenIn] + _amountIn; 
        uint totalReserve1 = reserve[lptokenAddr][_tokenOut] - amountOut;

        _update(lptokenAddr,_tokenIn, _tokenOut, totalReserve0, totalReserve1);
    }
    //交易携带滑点限制
    function swapByLimitSli(address _tokenIn, address _tokenOut, uint _amountIn, uint _disirSli) public returns(uint amountOut){
        require(
            findLpToken[_tokenIn][_tokenOut] != address(0),
            "invalid token"
        );
        require(_amountIn > 0, "amount in = 0");
        require(_tokenIn != _tokenOut);
        require(_amountIn >= 1000, "require amountIn >= 1000 wei token");

        IERC20 tokenIn = IERC20(_tokenIn);
        IERC20 tokenOut = IERC20(_tokenOut);
        address lptokenAddr = findLpToken[_tokenIn][_tokenOut];
        uint reserveIn = reserve[lptokenAddr][_tokenIn];
        uint reserveOut = reserve[lptokenAddr][_tokenOut];

        tokenIn.transferFrom(msg.sender, address(this), _amountIn);



        uint amountInWithFee = (_amountIn * 997) / 1000;
        amountOut = (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);

        //检查滑点
        setSli(amountInWithFee,reserveIn,reserveOut,_disirSli);


        tokenOut.transfer(msg.sender, amountOut);
        uint totalReserve0 = reserve[lptokenAddr][_tokenIn] + _amountIn; 
        uint totalReserve1 = reserve[lptokenAddr][_tokenOut] - amountOut;

        _update(lptokenAddr,_tokenIn, _tokenOut, totalReserve0, totalReserve1);

    }

    //borrow logic

    function borrowToken(address _lpAddr,address _token,uint _amount) public {
        uint tokenReserve = reserve[_lpAddr][_token];
        require(_amount < tokenReserve,"require smaller than reserve");
        IERC20 token = IERC20(_token);
        address user = msg.sender;

        token.transfer(msg.sender, _amount);

        findUserBorrowedAmount[user][_lpAddr][_token] += _amount;
        findBorrowedAmount[_lpAddr][_token] += _amount;
    }

    //暴露数据查询方法

    function getReserve(address _lpTokenAddr, address _tokenAddr) public view returns(uint)
    {
        return reserve[_lpTokenAddr][_tokenAddr];
    }

    function getLptoken(address _tokenA, address _tokenB) public view returns(address)
    {
        return findLpToken[_tokenA][_tokenB];
    }

    function getLpInfo(address _tokenA,address _tokenB) public view returns(uint tokenAReserve,uint tokenBReserve,uint tokenABorrowed,uint tokenBBorrowed,uint tokenABorrowedRate,uint tokenBBorrowedRate,uint lpTokenAApr,uint lpTokenBApr,uint borrowederTokenAApr,uint borrowederTokenBApr){
        tokenAReserve = getReserve(findLpToken[_tokenA][ _tokenB], _tokenA);
        tokenBReserve = getReserve(findLpToken[_tokenA][ _tokenB], _tokenB);
        tokenABorrowed = findBorrowedAmount[findLpToken[_tokenA][ _tokenB]][ _tokenA];
        tokenBBorrowed = findBorrowedAmount[findLpToken[_tokenA][ _tokenB]][ _tokenB];
        if((tokenABorrowed * ONE_ETH > tokenAReserve)){
            tokenABorrowedRate = ONE_ETH * tokenABorrowed / tokenAReserve;
        }else{
            tokenABorrowedRate = 0;
        }

        if((tokenBBorrowed * ONE_ETH > tokenBReserve)){
            tokenBBorrowedRate = ONE_ETH * tokenBBorrowed / tokenBReserve;
        }else{
            tokenABorrowedRate = 0;
        }
        lpTokenAApr = tokenABorrowedRate * tokenABorrowedRate / 10**18;
        lpTokenAApr = tokenBBorrowedRate * tokenBBorrowedRate / 10**18;
        borrowederTokenAApr = lpTokenAApr + 3*10**16;
        borrowederTokenBApr = lpTokenBApr + 3*10**16;
        
    }

    function lptokenTotalSupply(address _token0, address _token1, address user) public view returns(uint)
    {
        Lp lptoken;
        lptoken = Lp(findLpToken[_token0][_token1]);
        uint totalSupply = lptoken.balanceOf(user);
        return totalSupply;
    }

    function getLptokenLength() public view returns(uint)
    {
        return lpTokenAddressList.length;
    }

//依赖方法
    //creatpair

    function createPair(address addrToken0, address addrToken1) internal {
        bytes32 _salt = keccak256(
            abi.encodePacked(
                addrToken0,addrToken1
            )
        );
        new Lp{
            salt : bytes32(_salt)
        }
        ();

        address lptokenAddr = getAddress(getBytecode(),_salt);

         //检索lptoken
        lpTokenAddressList.push(lptokenAddr);
        findLpToken[addrToken0][addrToken1] = lptokenAddr;
        findLpToken[addrToken1][addrToken0] = lptokenAddr;

    }

    function getBytecode() internal pure returns(bytes memory) {
        bytes memory bytecode = type(Lp).creationCode;
        return bytecode;
    }

    function getAddress(bytes memory bytecode, bytes32 _salt)
        internal
        view
        returns(address)
    {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), address(this), _salt, keccak256(bytecode)
            )
        );

        return address(uint160(uint(hash)));
    }

    //数据更新

    function _update(address lptokenAddr,address _token0, address _token1, uint _reserve0, uint _reserve1) private {
        reserve[lptokenAddr][_token0] = _reserve0;
        reserve[lptokenAddr][_token1] = _reserve1;
    }

//数学库

    function _sqrt(uint y) private pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }

    function setSli(uint dx, uint x, uint y, uint _disirSli) private pure returns(uint){


        uint amountOut = (y * dx) / (x + dx);

        uint dy = dx * y/x;
        /*
        loseAmount = Idea - ammOut
        Sli = loseAmount/Idea
        Sli = [dx*y/x - y*dx/(dx + x)]/dx*y/x
        */
        uint loseAmount = dy - amountOut;

        uint Sli = loseAmount * 10000 /dy;
        
        require(Sli <= _disirSli, "Sli too large");
        return Sli;

    }



}
