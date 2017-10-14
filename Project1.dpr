library Cash;

uses
  Windows,
  DDetours,
  DX12.D3D11,
  Dx12.DXGI,
  DX12.D3DCommon,
  DX12.D3DCompiler,
  DX12D3D10,
  Dx12.D3DX10;

{$R *.res}

var
  RunOnce: Boolean;
  ThreadID: DWord;
  SwapChainDesc: TDXGI_SWAP_CHAIN_DESC;
  pDevice: ID3D11Device;
  pContext: ID3D11DeviceContext;
  pFeature: TD3D_FEATURE_LEVEL;
  pSwapChain: IDXGISwapChain;
  psRed: ID3D11PixelShader;
  StencilDesc: TD3D11_DEPTH_STENCIL_DESC;
  FDepthStencilState: ID3D11DepthStencilState;

var
  OriginalPresent: function(pSwapChain: IDXGISwapChain; SyncInterval: UInt; Flags: UInt): HResult; stdcall = nil;
  OriginalDrawIndexed: procedure(pContext: ID3D11DeviceContext; IndexCount: UInt; StartIndexLocation: UInt; BaseVertexLocation: Integer); stdcall;
  OriginalDraw: procedure(pContext: ID3D11DeviceContext; VertexCount: UInt; StartVertexLocation: UInt); stdcall;


function InitialiseShader(pDevice: ID3D11Device; pShader: ID3D11PixelShader): HResult;
var
  pBlob, pErrorMsgs: ID3DBlob;
begin
  Result := D3DCompileFromFile(PWideChar(WideString('C:\PixelShader.ps')), nil, nil, 'PSEntry', 'ps_4_0', 0, 0, pBlob, pErrorMsgs);
  if Failed(Result) then
  begin
    //Log('컴파일에러');
    exit;
  end;
  Result := pDevice.CreatePixelShader(pBlob.GetBufferPointer, pBlob.GetBufferSize, nil, psRed);
  if Failed(Result) then
  begin
    //Log('PixelShader생성 실패.');
    exit;
  end;
end;

function csPresent(pSwapChain: IDXGISwapChain; SyncInterval: UInt; Flags: UInt): HResult; stdcall;
begin
  if RunOnce then
  begin
    pSwapChain.GetDevice(TGUID(ID3D11Device), Pointer(pDevice));
    pDevice.GetImmediateContext(pContext);
    with StencilDesc do
    begin
      DepthEnable := True;
      DepthWriteMask := D3D11_DEPTH_WRITE_MASK_ALL;
      DepthFunc := D3D11_COMPARISON_LESS;
      StencilEnable := True;
      StencilReadMask := $FF;
      StencilWriteMask := $FF;
      FrontFace.StencilFailOp := D3D11_STENCIL_OP_KEEP;
      FrontFace.StencilDepthFailOp := D3D11_STENCIL_OP_INCR;
      FrontFace.StencilPassOp := D3D11_STENCIL_OP_KEEP;
      FrontFace.StencilFunc := D3D11_COMPARISON_ALWAYS;
      BackFace.StencilFailOp := D3D11_STENCIL_OP_KEEP;
      BackFace.StencilDepthFailOp := D3D11_STENCIL_OP_DECR;
      BackFace.StencilPassOp := D3D11_STENCIL_OP_KEEP;
      BackFace.StencilFunc := D3D11_COMPARISON_ALWAYS;
    end;
    pDevice.CreateDepthStencilState(StencilDesc, FDepthStencilState);
    StencilDesc.DepthEnable := false;
    StencilDesc.DepthWriteMask := D3D11_DEPTH_WRITE_MASK_ALL;
    pDevice.CreateDepthStencilState(StencilDesc, FDepthStencilState);
    //Log('cdPresent1.');
    RunOnce := False;
  end;
  InitialiseShader(pDevice, psRed);
  Result := OriginalPresent(pSwapChain, SyncInterval, Flags);
end;

procedure csDraw(pContext: ID3D11DeviceContext; VertexCount: UInt; StartVertexLocation: UInt); stdcall;
begin
  //Log('csDraw1');
  OriginalDraw(pContext, VertexCount, StartVertexLocation);
end;

procedure csDrawIndexed(pContext: ID3D11DeviceContext; IndexCount: UInt; StartIndexLocation: UInt; BaseVertexLocation: Integer); stdcall;
var
  Stride, BufferOffset: UInt;
  vBuffer: ID3D11Buffer;
  vDesc: TD3D11_BUFFER_DESC;
begin
  pContext.IAGetVertexBuffers(0, 1, vBuffer, Stride, BufferOffset);
  vBuffer.GetDesc(vDesc);
  if Stride = 36 then
  begin
    pContext.OMSetDepthStencilState(FDepthStencilState, 1);
    pContext.PSSetShader(psRed, nil, 0);
    OriginalDrawIndexed(pContext, IndexCount, StartIndexLocation, BaseVertexLocation);
    //Log('IndexCount: '+IntToStr(IndexCount)+' StartIndexLocation: '+IntToStr(StartIndexLocation)+' BaseVertexLocation: '+IntToStr(BaseVertexLocation)+' Stride: '+IntToStr(Stride)+' BufferOffest: '+IntToStr(BufferOffset));
  end;
  OriginalDrawIndexed(pContext, IndexCount, StartIndexLocation, BaseVertexLocation);
end;

function InitialiseHook: HResult;
var
  Handle: THandle;
  FeatureLevel: Array[0..0] of TD3D_FEATURE_LEVEL;
begin
  Handle := GetForegroundWindow;
  FillChar(SwapChainDesc, SizeOf(SwapChainDesc), 0);
  with SwapChainDesc do
  begin
    BufferCount := 1;
    BufferUsage := DXGI_USAGE_RENDER_TARGET_OUTPUT;
    OutputWindow := Handle;
    SampleDesc.Count := 1;
    Windowed := True;
    BufferDesc.Format := DXGI_FORMAT_R8G8B8A8_UNORM;
    BufferDesc.ScanlineOrdering := DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED;
    BufferDesc.Scaling := DXGI_MODE_SCALING_UNSPECIFIED;
    SwapEffect := DXGI_SWAP_EFFECT_DISCARD;
  end;
  FeatureLevel[0] := D3D_FEATURE_LEVEL_11_0;
  Result := D3D11CreateDeviceAndSwapChain(nil, D3D_DRIVER_TYPE_HARDWARE, 0, 0,  @FeatureLevel[0], 1, D3D11_SDK_VERSION,
  @swapChainDesc, pSwapChain, pDevice, pFeature, pContext);
  if Succeeded(Result) then
  begin
     @originalPresent := InterceptCreate(Pointer(PNativeUint(PNativeUint(pSwapChain)^ + $40)^), @csPresent);
     @originalDrawIndexed := InterceptCreate(Pointer(PNativeUint(PNativeUint(pContext)^ + $60)^), @csDrawIndexed);
     @originalDraw := InterceptCreate(Pointer(PNativeUint(PNativeUint(pContext)^ + $68)^), @csDraw);
    exit;
  end;
  //Log('디바이스생성실패');
end;

procedure DLLEntry(dwReason: DWord);
begin
  case dwReason of
    DLL_PROCESS_ATTACH:
    begin
      RunOnce := True;
      CreateThread(nil, 0,  @InitialiseHook, nil, 0, ThreadID);
    end;
    DLL_PROCESS_DETACH:
    begin
      exit;
    end;
  end;
end;

begin
  DLLProc :=  @dLLEntry;
  DLLEntry(DLL_PROCESS_ATTACH);
end.
