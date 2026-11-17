#nullable disable
using System.Runtime.InteropServices;
using System.Security.Cryptography;
namespace ExcelPasswordSafe.Crypto {
    internal static class TestMemory {
        internal static readonly Dictionary<IntPtr,int> Allocations=new Dictionary<IntPtr,int>();
        internal static int ClearedFrees;
        internal static IntPtr AllocHGlobal(int length){IntPtr p=Marshal.AllocHGlobal(length);Allocations.Add(p,length);return p;}
        internal static bool IsZero(IntPtr p){for(int i=0;i<Allocations[p];i++)if(Marshal.ReadByte(p,i)!=0)return false;return true;}
        internal static void FreeHGlobal(IntPtr p){if(!IsZero(p))throw new Exception("Native object was not cleared");ClearedFrees++;Allocations.Remove(p);Marshal.FreeHGlobal(p);}
        internal static void ReleaseRetained(){foreach(IntPtr p in Allocations.Keys.ToArray()){if(!IsZero(p))throw new Exception("Retained native buffer was not cleared");Allocations.Remove(p);Marshal.FreeHGlobal(p);}}
    }
    // This replacement is compiled only into the isolated test EXE. No fault
    // selectors, fake handles, or mutable delegates exist in the product DLL.
    internal static class NativeHashApi {
        internal const int Failure=unchecked((int)0xC0000001);
        internal static string Fault;
        internal static int OpenCalls,CreateCalls,DestroyCalls,CloseCalls,FinishCalls,CancelAt;
        internal static CancellationTokenSource Cancellation;
        internal static readonly List<byte[]> ObservedArrays=new List<byte[]>();
        private static byte[] lastInput;
        internal static void Reset(string fault){Fault=fault;OpenCalls=CreateCalls=DestroyCalls=CloseCalls=FinishCalls=CancelAt=0;Cancellation=null;ObservedArrays.Clear();TestMemory.ClearedFrees=0;lastInput=null;}
        internal static int OpenAlgorithm(out IntPtr handle,string name,string provider,uint flags){OpenCalls++;handle=Fault=="Open"?IntPtr.Zero:new IntPtr(11);return Fault=="Open"?Failure:0;}
        internal static int GetProperty(IntPtr handle,string name,out int result,int length,out int returned,uint flags){result=name=="ObjectLength"?128:64;returned=4;if(Fault=="Length")result=63;return Fault=="Property"?Failure:0;}
        internal static int CreateHash(IntPtr algorithm,out IntPtr hash,IntPtr buffer,int length,IntPtr secret,int secretLength,uint flags){
            CreateCalls++;for(int i=0;i<length;i++)Marshal.WriteByte(buffer,i,0x5a);hash=Fault=="Create"?IntPtr.Zero:new IntPtr(22);return Fault=="Create"?Failure:0;
        }
        internal static int HashData(IntPtr hash,byte[] input,int length,uint flags){
            ObservedArrays.Add(input);lastInput=input;return Fault=="HashData"?Failure:0;
        }
        internal static int FinishHash(IntPtr hash,byte[] output,int length,uint flags){
            ObservedArrays.Add(output);FinishCalls++;
            using(var sha=SHA512.Create()){byte[] bytes=sha.ComputeHash(lastInput);Buffer.BlockCopy(bytes,0,output,0,output.Length);Array.Clear(bytes,0,bytes.Length);}
            if(Cancellation!=null && FinishCalls==CancelAt)Cancellation.Cancel();
            return Fault=="Finish"?Failure:0;
        }
        internal static int DestroyHash(IntPtr hash){DestroyCalls++;return Fault=="Destroy"?Failure:0;}
        internal static int CloseAlgorithm(IntPtr handle,uint flags){CloseCalls++;return Fault=="Close"?Failure:0;}
    }
    internal static class FaultProgram {
        private static int checks;
        private static void Assert(bool value,string name){checks++;if(!value)throw new Exception(name);}
        private static bool Zero(byte[] bytes){return bytes.All(value=>value==0);}
        private static void One(string fault,int spins,int cancelAt){
            NativeHashApi.Reset(fault);byte[] input={4,8,15,16,23,42},output=null;
            bool failed=false;using(var cancellation=new CancellationTokenSource()){
                NativeHashApi.Cancellation=cancellation;NativeHashApi.CancelAt=cancelAt;
                if(fault=="CancelBefore")cancellation.Cancel();
                try{output=NativePasswordHash.Derive(input,spins,"SHA512",cancellation.Token);}
                catch(CryptographicException){failed=true;}
                catch(OperationCanceledException){failed=true;}
                finally{if(output!=null)Array.Clear(output,0,output.Length);}
            }
            Assert(failed==(fault!="Success"),fault+" expected failure status");
            Assert(Zero(input)&&NativeHashApi.ObservedArrays.All(Zero),fault+" all managed inputs/digests cleared");
            Assert(TestMemory.Allocations.Count==(fault=="Destroy"?1:0),fault+" no live native allocation except retained uncertain owner");
            if(fault=="Destroy")Assert(TestMemory.Allocations.Keys.All(TestMemory.IsZero),"Destroy failure retains zeroed buffer");
            if(NativeHashApi.CreateCalls>0)Assert(TestMemory.ClearedFrees==(fault=="Destroy"?0:1),fault+" native object cleared before free");
            if(fault=="Success")Assert(NativeHashApi.FinishCalls==spins+1,"Exactly initial plus all requested spins");
            if(cancelAt>0)Assert(NativeHashApi.FinishCalls==cancelAt,fault+" cancellation boundary unchanged");
            if(fault!="Open"&&fault!="CancelBefore")Assert(NativeHashApi.CloseCalls==1,fault+" algorithm cleanup attempted");
            if(fault=="CancelBefore")Assert(NativeHashApi.OpenCalls==0,"Pre-cancel opens no provider");
            TestMemory.ReleaseRetained();
        }
        public static int Main(){
            try{
                foreach(string fault in new[]{"Success","Open","Property","Length","Create","HashData","Finish","Destroy","Close","CancelBefore"})One(fault,3,0);
                One("CancelMiddle",2048,1025);One("CancelAfter",2,3);
                Console.WriteLine("PASS "+checks);return 0;
            }catch(Exception error){Console.Error.WriteLine("FAIL "+error.Message);return 1;}
            finally{TestMemory.ReleaseRetained();}
        }
    }
}
