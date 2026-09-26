using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace VisibleCellsPaste {
 // Record every COM-return acquisition, including repeated identities. Borrowed references never enter this scope.
 public sealed class ComScope : IDisposable {
  readonly List<object> owned=new List<object>(); readonly Action<object> release; bool disposed;
  public ComScope():this(ReleaseOne){}
  internal ComScope(Action<object> releaseOne){if(releaseOne==null)throw new ArgumentNullException("releaseOne");release=releaseOne;}
  static void ReleaseOne(object value){if(value!=null&&Marshal.IsComObject(value))try{Marshal.ReleaseComObject(value);}catch(InvalidComObjectException){}}
  public object Own(object value){
   if(disposed){if(value!=null)release(value);throw new ObjectDisposedException("ComScope");}
   if(value!=null)owned.Add(value);return value;
  }
  public void Dispose(){
   if(disposed)return;disposed=true;Exception first=null;
   for(int i=owned.Count-1;i>=0;i--)try{release(owned[i]);}catch(Exception error){if(first==null)first=error;}
   owned.Clear();if(first!=null)throw first;
  }
 }
}
