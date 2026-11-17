using System;
using System.Collections.Generic;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
public static class NativeKdfTests {
    public sealed class Check { public string Name; public bool Passed; }
    public static readonly List<Check> Checks=new List<Check>();
    private static MethodInfo native,legacy,dispatch;
    private static void Assert(string name,bool pass){Checks.Add(new Check{Name=name,Passed=pass});if(!pass)throw new Exception(name);}
    private static byte[] Invoke(MethodInfo method,params object[] args){try{return (byte[])method.Invoke(null,args);}catch(TargetInvocationException error){throw error.InnerException;}}
    private static bool Equal(byte[] a,byte[] b){if(a.Length!=b.Length)return false;int n=0;for(int i=0;i<a.Length;i++)n|=a[i]^b[i];return n==0;}
    private static bool Zero(byte[] bytes){foreach(byte value in bytes)if(value!=0)return false;return true;}
    private static void Clear(byte[] bytes){if(bytes!=null)Array.Clear(bytes,0,bytes.Length);}
    private static void Compare(string algorithm,byte[] initial,int spins,string label){
        byte[] originalInput=(byte[])initial.Clone(),nativeInput=(byte[])initial.Clone(),expected=null,actual=null;
        try {
            expected=Invoke(legacy,originalInput,spins,algorithm,CancellationToken.None);
            actual=Invoke(native,nativeInput,spins,algorithm,CancellationToken.None);
            Assert(label+" equals pinned legacy",Equal(expected,actual));
            Assert(label+" consumes and clears input",Zero(nativeInput));
        }finally{Clear(originalInput);Clear(nativeInput);Clear(expected);Clear(actual);}
    }
    public static void Run(string assemblyPath){
        Assembly assembly=Assembly.LoadFrom(assemblyPath);
        const BindingFlags flags=BindingFlags.NonPublic|BindingFlags.Static;
        native=assembly.GetType("ExcelPasswordSafe.Crypto.NativePasswordHash",true).GetMethod("Derive",flags);
        Type codec=assembly.GetType("OfficeIMO.Core.Internal.OfficeEncryption",true);
        legacy=codec.GetMethod("DerivePasswordHashLegacy",flags);dispatch=codec.GetMethod("DerivePasswordHash",flags);
        string[] algorithms={"SHA256","SHA512"};
        string[] emptyHashes={"E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855","CF83E1357EEFB8BDF1542850D66D8007D620E4050B5715DC83F4A921D36CE9CE47D0D13C5D85F2B0FF8318D2877EEC2F63B931BD47417A81A538327AF927DA3E"};
        for(int algorithmIndex=0;algorithmIndex<algorithms.Length;algorithmIndex++){
            string algorithm=algorithms[algorithmIndex];
            byte[] known=Invoke(native,new byte[0],0,algorithm,CancellationToken.None);
            try{Assert(algorithm+" empty-message known answer",BitConverter.ToString(known).Replace("-","")==emptyHashes[algorithmIndex]);}finally{Clear(known);}
            int[] lengths=algorithm=="SHA256"?new[]{0,1,55,56,63,64,65}:new[]{0,1,111,112,127,128,129};
            foreach(int length in lengths){byte[] input=new byte[length];for(int i=0;i<length;i++)input[i]=(byte)(i*17+3);Compare(algorithm,input,1,algorithm+" boundary "+length);Clear(input);}
            foreach(string password in new[]{"","Test"+(char)0xd55c+(char)0xae00+"42!"}){
                byte[] salt=new byte[16];for(int i=0;i<salt.Length;i++)salt[i]=(byte)(i*11);
                byte[] passwordBytes=Encoding.Unicode.GetBytes(password),initial=new byte[salt.Length+passwordBytes.Length];
                Buffer.BlockCopy(salt,0,initial,0,salt.Length);Buffer.BlockCopy(passwordBytes,0,initial,salt.Length,passwordBytes.Length);
                string label=algorithm+(password.Length==0?" empty password":" Unicode password");
                Compare(algorithm,initial,1024,label+" 1024 spins");
                byte[] expected=null,actual=null;
                try {
                    expected=Invoke(legacy,initial,100000,algorithm,CancellationToken.None);
                    actual=Invoke(dispatch,password,salt,100000,algorithm,CancellationToken.None);
                    Assert(label+" production dispatch 100000 spins",Equal(expected,actual));
                }finally{Clear(expected);Clear(actual);Clear(initial);Clear(passwordBytes);Clear(salt);}
            }
            byte[] cancelledInput=new byte[]{3,7,11};
            using(var token=new CancellationTokenSource()){
                token.Cancel();bool cancelled=false;
                try{Clear(Invoke(native,cancelledInput,100000,algorithm,token.Token));}catch(OperationCanceledException){cancelled=true;}
                Assert(algorithm+" cancellation before native allocation",cancelled);
                Assert(algorithm+" cancelled input cleared",Zero(cancelledInput));
            }
        }
        // Exercise unmanaged object lifetime through compacting collections while
        // real BCrypt calls are running, without adding any product test switch.
        byte[] pressureInput=new byte[128];for(int i=0;i<pressureInput.Length;i++)pressureInput[i]=(byte)i;
        byte[] expectedPressure=Invoke(legacy,(byte[])pressureInput.Clone(),100000,"SHA512",CancellationToken.None),actualPressure=null;
        using(var timer=new Timer(delegate(object state){GC.Collect(2,GCCollectionMode.Forced,true);},null,0,5)){
            try{actualPressure=Invoke(native,pressureInput,100000,"SHA512",CancellationToken.None);Assert("Native object survives GC pressure",Equal(expectedPressure,actualPressure));}
            finally{Clear(expectedPressure);Clear(actualPressure);Clear(pressureInput);}
        }
    }
}
