using System;
using System.Windows.Forms;
namespace VisibleCellsPaste {
 internal sealed class ProgressDialog:Form {
  bool complete; public void Finish(){complete=true;Close();}
  readonly Label stage=new Label();readonly Button cancel=new Button();public bool Canceled{get;private set;}
  public ProgressDialog(){Text="보이는 칸 붙여넣기";Width=370;Height=130;FormBorderStyle=FormBorderStyle.FixedDialog;MaximizeBox=false;MinimizeBox=false;StartPosition=FormStartPosition.CenterParent;stage.SetBounds(16,12,320,28);cancel.Text="취소";cancel.SetBounds(252,48,84,28);cancel.Click+=delegate{Canceled=true;cancel.Enabled=false;stage.Text="복구를 준비하고 있습니다.";};Controls.Add(stage);Controls.Add(cancel);FormClosing+=delegate(object s,FormClosingEventArgs e){if(!complete&&e.CloseReason==CloseReason.UserClosing){Canceled=true;e.Cancel=true;}};}
  public void SetStage(string text){stage.Text=text;Application.DoEvents();}
 }
}
