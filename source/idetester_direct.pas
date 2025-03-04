unit idetester_direct;

{
Copyright (c) 2011+, Health Intersections Pty Ltd (http://www.healthintersections.com.au)
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
 * Neither the name of HL7 nor the names of its contributors may be used to
   endorse or promote products derived from this software without specific
   prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 'AS IS' AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
}

{$MODE DELPHI}

interface

uses
  Classes, SysUtils,
  FPCUnit, testregistry, testdecorator,
  idetester_base, idetester_strings;

type
  { TTestSessionDirect }

  TTestSessionDirect = class (TTestSession)
  private
    FTestResult : TTestResult;
  public
    constructor Create;
    destructor Destroy; override;
    procedure skipTest(node : TTestNode); override;
  end;

  { TTestEngineDirectListener }

  TTestEngineDirectListener = class (TinterfacedObject, ITestListener)
  private
    FListener : TTestListener;
    FRoot : TTestNode;
    function findTestInNode(test : TTest; node : TTestNode) : TTestNode;
    function findNode(test : TTest; optional : boolean = false) : TTestNode;
    function makeError(err : TTestFailure) : TTestError;
  public
    constructor create(listener : TTestListener; root : TTestNode);

    procedure StartTest(ATest: TTest);
    procedure EndTest(ATest: TTest);
    procedure StartTestSuite(ATestSuite: TTestSuite);
    procedure EndTestSuite(ATestSuite: TTestSuite);
    procedure AddFailure(ATest: TTest; AFailure: TTestFailure);
    procedure AddError(ATest: TTest; AError: TTestFailure);
  end;

  { TTestEngineDirect }

  TTestEngineDirect = class (TTestEngine)
  private
    FSess: TTestSessionDirect;
    FNode: TTestNode;
    FThreadMode: TTestEngineThreadMode;
    Function registerTestNode(testList : TTestNodeList; parent : TTestNode; test : TTest) : TTestNode;
    procedure BuildTree(testList : TTestNodeList; rootTest: TTestNode; aSuite: TTestSuite);
    procedure runTestSynchronized;
  public
    constructor Create;
    procedure loadAllTests(testList : TTestNodeList; manual : boolean); override;
    function threadMode : TTestEngineThreadMode; override;
    function canTerminate : boolean; override;
    function doesReload : boolean; override;
    function canDebug : boolean; override;
    function canStart : boolean; override;

    function prepareToRunTests(aTestThread: TThread = nil) : TTestSession; override;
    procedure runTest(session : TTestSession; node : TTestNode); override;
    procedure terminateTests(session: TTestSession); override;
    procedure finishTestRun(session : TTestSession); override;
    procedure setThreadModeMainThread; override;
  end;


implementation

{ TTestEngineDirectListener }

constructor TTestEngineDirectListener.create(listener: TTestListener; root: TTestNode);
begin
  inherited Create;
  FListener := listener;
  FRoot := root;
end;

function TTestEngineDirectListener.findTestInNode(test: TTest; node: TTestNode): TTestNode;
var
  child, t : TTestNode;
begin
  if node.Data = test then
    result := node
  else
  begin
    result := nil;
    for child in node.children do
    begin
      t := findTestInNode(test, child);
      if (t <> nil) then
        exit(t);
    end;
  end;
end;

function TTestEngineDirectListener.findNode(test : TTest; optional : boolean) : TTestNode;
begin
  result := findTestInNode(test, FRoot);
  if (result = nil) and not optional then
    raise EIDETester.create(Format(rs_IdeTester_Err_Node_Not_Found, [test.TestName])); // this really shouldn't happen
end;

function TTestEngineDirectListener.makeError(err : TTestFailure) : TTestError;
var
  src : String;
  line : integer;
begin
  result := TTestError.create;
  result.ExceptionClass := err.ExceptionClass.ClassName;
  result.ExceptionMessage := err.ExceptionMessage;
  readLocation(err.LocationInfo, src, line);
  result.SourceUnit := src;
  result.LineNumber := line;
end;

procedure TTestEngineDirectListener.StartTest(ATest: TTest);
begin
  FListener.StartTest(findNode(ATest));
end;

procedure TTestEngineDirectListener.EndTest(ATest: TTest);
begin
  FListener.EndTest(findNode(ATest));
end;

procedure TTestEngineDirectListener.StartTestSuite(ATestSuite: TTestSuite);
var
  node : TTestNode;
begin
  node := findNode(ATestSuite, true);
  if (node <> nil) then
    FListener.StartTestSuite(node);
end;

procedure TTestEngineDirectListener.EndTestSuite(ATestSuite: TTestSuite);
var
  node : TTestNode;
begin
  node := findNode(ATestSuite, true);
  if (node <> nil) then
    FListener.EndTestSuite(node);
end;

procedure TTestEngineDirectListener.AddFailure(ATest: TTest; AFailure: TTestFailure);
var
  err : TTestError;
begin
  err := makeError(aFailure);
  try
    FListener.TestFailure(findNode(ATest), err);
  finally
    err.Free;
  end;
end;

procedure TTestEngineDirectListener.AddError(ATest: TTest; AError: TTestFailure);
var
  err : TTestError;
begin
  err := makeError(aError);
  try
    FListener.TestError(findNode(ATest), err);
  finally
    err.Free;
  end;
end;

{ TTestSessionDirect }

constructor TTestSessionDirect.Create;
begin
  inherited Create;
  FTestResult := TTestResult.Create;
end;

destructor TTestSessionDirect.Destroy;
begin
  FreeAndNil(FTestResult);
  inherited Destroy;
end;

procedure TTestSessionDirect.skipTest(node: TTestNode);
begin
 if (node.data is TTestCase) then
   FTestResult.AddToSkipList(node.data as TTestCase);
end;

{ TTestEngineDirect }

procedure TTestEngineDirect.loadAllTests(testList : TTestNodeList; manual : boolean);
var
  test : TTestSuite;
  node : TTestNode;
begin
  test := GetTestRegistry;
  node := registerTestNode(testList, nil, test);
  BuildTree(testList, node, test);
end;

function TTestEngineDirect.registerTestNode(testList : TTestNodeList; parent: TTestNode; test: TTest): TTestNode;
begin
  result := TTestNode.create(parent);
  testlist.add(result);
  if (parent <> nil) then
    parent.Children.add(result);
  result.Data := test;
  result.testName := test.TestName;
  result.SourceUnit := test.UnitName;
  result.testClassName := test.ClassName;
  result.checkState := tcsUnchecked;
  result.outcome := toNotRun;
end;

procedure TTestEngineDirect.BuildTree(testList : TTestNodeList; rootTest: TTestNode; aSuite: TTestSuite);
var
  test: TTestNode;
  i: integer;
begin
  for i := 0 to ASuite.ChildTestCount - 1 do
  begin
    if (ASuite.Test[i].TestName = '') and (ASuite.ChildTestCount = 1) then
      test := rootTest
    else
      test := registerTestNode(testList, rootTest, ASuite.Test[i]);

    if ASuite.Test[i] is TTestSuite then
      BuildTree(testList, test, TTestSuite(ASuite.Test[i]))
    else if TObject(ASuite.Test[i]).InheritsFrom(TTestDecorator) then
      BuildTree(testList, test, TTestSuite(TTestDecorator(ASuite.Test[i]).Test));
  end;
end;

procedure TTestEngineDirect.runTestSynchronized;
begin
  (FNode.data as TTest).Run(FSess.FTestResult);
end;

constructor TTestEngineDirect.Create;
begin
  FThreadMode:=ttmEither;
end;

function TTestEngineDirect.threadMode: TTestEngineThreadMode;
begin
  result := FThreadMode;
end;

function TTestEngineDirect.canTerminate: boolean;
begin
  result := false;
end;

function TTestEngineDirect.doesReload: boolean;
begin
  result := false;
end;

function TTestEngineDirect.canDebug: boolean;
begin
  result := false;
end;

function TTestEngineDirect.canStart: boolean;
begin
  result := true;
end;

function TTestEngineDirect.prepareToRunTests(aTestThread: TThread = nil): TTestSession;
begin
  FTestThread := aTestThread;
  result := TTestSessionDirect.Create;
end;

procedure TTestEngineDirect.runTest(session: TTestSession; node: TTestNode);
var
  listenerProxy : ITestListener;
begin
  listenerProxy := TTestEngineDirectListener.create(listener, node) as ITestListener;

  FSess := session as TTestSessionDirect;
  FNode := node;
  try
    FSess.FTestResult.AddListener(listenerProxy);
    if (node.data is TTestSuite) then
      listener.StartTestSuite(node);
    try
      if Assigned(FTestThread) and (threadMode = ttmMainThread)
      then TThread.Synchronize(FTestThread, runTestSynchronized)
      else (FNode.data as TTest).Run(FSess.FTestResult);
    finally
      if (node.data is TTestSuite) then
        listener.EndTestSuite(node);
    end;
    FSess.FTestResult.RemoveListener(listenerProxy);
  finally
    listener.EndRun(node);
    listenerProxy := nil;
  end;
end;

procedure TTestEngineDirect.terminateTests(session: TTestSession);
begin
  raise EIDETester.create(rs_IdeTester_Msg_NOT_SUPPORTED);
end;

procedure TTestEngineDirect.finishTestRun(session: TTestSession);
begin
  session.free;
end;

procedure TTestEngineDirect.setThreadModeMainThread;
begin
  FThreadMode:=ttmMainThread;
end;

end.

