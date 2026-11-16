using System.Windows;
using System.Windows.Markup;

namespace ExcelPasswordSafe
{
    public static class AppTheme
    {
        public static ResourceDictionary Create()
        {
            return (ResourceDictionary)XamlReader.Parse(@"<ResourceDictionary xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>
<Style TargetType='Button'>
 <Setter Property='Padding' Value='16,10'/><Setter Property='MinHeight' Value='42'/><Setter Property='FontWeight' Value='SemiBold'/><Setter Property='Background' Value='White'/><Setter Property='Foreground' Value='#344460'/><Setter Property='BorderBrush' Value='#D9E0ED'/><Setter Property='BorderThickness' Value='1'/><Setter Property='Cursor' Value='Hand'/><Setter Property='FocusVisualStyle' Value='{x:Null}'/>
 <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='Button'><Grid>
  <Border CornerRadius='9' Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}' BorderThickness='{TemplateBinding BorderThickness}' Padding='{TemplateBinding Padding}'><ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center' RecognizesAccessKey='True'/></Border>
  <Border x:Name='focus' CornerRadius='9' BorderThickness='2' BorderBrush='#8799EA' Opacity='0' IsHitTestVisible='False'/>
 </Grid><ControlTemplate.Triggers><Trigger Property='IsKeyboardFocused' Value='True'><Setter TargetName='focus' Property='Opacity' Value='1'/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
 <Style.Triggers><Trigger Property='IsMouseOver' Value='True'><Setter Property='Background' Value='#F0F3FA'/><Setter Property='BorderBrush' Value='#A6B4D3'/></Trigger><Trigger Property='IsPressed' Value='True'><Setter Property='Background' Value='#E6ECF8'/></Trigger><Trigger Property='IsEnabled' Value='False'><Setter Property='Background' Value='#EDF1F7'/><Setter Property='Foreground' Value='#8A97AC'/><Setter Property='BorderBrush' Value='#E1E7F0'/><Setter Property='Cursor' Value='Arrow'/></Trigger></Style.Triggers>
</Style>
<Style x:Key='PrimaryButton' TargetType='Button' BasedOn='{StaticResource {x:Type Button}}'>
 <Setter Property='Background' Value='#3659D9'/><Setter Property='Foreground' Value='White'/><Setter Property='BorderBrush' Value='#3659D9'/>
 <Style.Triggers><Trigger Property='IsMouseOver' Value='True'><Setter Property='Background' Value='#294BC8'/><Setter Property='BorderBrush' Value='#294BC8'/></Trigger><Trigger Property='IsPressed' Value='True'><Setter Property='Background' Value='#2341B4'/><Setter Property='BorderBrush' Value='#2341B4'/></Trigger><Trigger Property='IsEnabled' Value='False'><Setter Property='Background' Value='#E0E6F5'/><Setter Property='Foreground' Value='#8997B5'/><Setter Property='BorderBrush' Value='#E0E6F5'/></Trigger></Style.Triggers>
</Style>
<Style x:Key='QuietButton' TargetType='Button' BasedOn='{StaticResource {x:Type Button}}'><Setter Property='Background' Value='Transparent'/><Setter Property='BorderBrush' Value='Transparent'/><Setter Property='Foreground' Value='#3659D9'/><Setter Property='Padding' Value='8,8'/><Setter Property='FontSize' Value='12'/></Style>
<Style TargetType='PasswordBox'>
 <Setter Property='Padding' Value='13,10'/><Setter Property='MinHeight' Value='44'/><Setter Property='FontSize' Value='14'/><Setter Property='BorderBrush' Value='#D5DDEA'/><Setter Property='Background' Value='White'/><Setter Property='Foreground' Value='#17223B'/><Setter Property='FocusVisualStyle' Value='{x:Null}'/>
 <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='PasswordBox'><Grid>
  <Border x:Name='field' CornerRadius='9' Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}' BorderThickness='1'/><ScrollViewer x:Name='PART_ContentHost'/>
  <Border x:Name='focus' CornerRadius='9' BorderBrush='#5A74DF' BorderThickness='2' Opacity='0' IsHitTestVisible='False'/>
 </Grid><ControlTemplate.Triggers><Trigger Property='IsMouseOver' Value='True'><Setter TargetName='field' Property='BorderBrush' Value='#9CADCD'/></Trigger><Trigger Property='IsKeyboardFocusWithin' Value='True'><Setter TargetName='focus' Property='Opacity' Value='1'/></Trigger><Trigger Property='IsEnabled' Value='False'><Setter TargetName='field' Property='Background' Value='#EDF1F7'/><Setter Property='Foreground' Value='#8794AA'/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
</Style>
<Style TargetType='RadioButton'>
 <Setter Property='Padding' Value='8,10'/><Setter Property='Margin' Value='2,0'/><Setter Property='Foreground' Value='#52637F'/><Setter Property='Background' Value='Transparent'/><Setter Property='BorderBrush' Value='Transparent'/><Setter Property='Cursor' Value='Hand'/><Setter Property='FocusVisualStyle' Value='{x:Null}'/>
 <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='RadioButton'><Grid><Border x:Name='panel' CornerRadius='8' BorderThickness='1' Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}' Padding='{TemplateBinding Padding}'><ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/></Border><Border x:Name='focus' CornerRadius='8' BorderThickness='2' BorderBrush='#7C91E5' Opacity='0' IsHitTestVisible='False'/></Grid><ControlTemplate.Triggers>
  <Trigger Property='IsMouseOver' Value='True'><Setter TargetName='panel' Property='Background' Value='#F3F6FD'/></Trigger>
  <Trigger Property='IsChecked' Value='True'><Setter TargetName='panel' Property='Background' Value='White'/><Setter TargetName='panel' Property='BorderBrush' Value='#D8E0F1'/><Setter Property='Foreground' Value='#3659D9'/><Setter Property='FontWeight' Value='Bold'/></Trigger>
  <Trigger Property='IsKeyboardFocused' Value='True'><Setter TargetName='focus' Property='Opacity' Value='1'/></Trigger><Trigger Property='IsEnabled' Value='False'><Setter Property='Opacity' Value='0.5'/><Setter Property='Cursor' Value='Arrow'/></Trigger>
 </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
</Style>
<Style TargetType='CheckBox'>
 <Setter Property='FocusVisualStyle' Value='{x:Null}'/><Setter Property='Cursor' Value='Hand'/><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='CheckBox'><Grid><Grid.ColumnDefinitions><ColumnDefinition Width='26'/><ColumnDefinition Width='*'/></Grid.ColumnDefinitions>
  <Grid Width='18' Height='18' VerticalAlignment='Top' HorizontalAlignment='Left' Margin='0,2,0,0'><Border x:Name='box' CornerRadius='4' Background='White' BorderBrush='#BAC6DC' BorderThickness='1'/><Path x:Name='tick' Data='M 4,9 L 7,12 L 14,5' Stroke='White' StrokeThickness='1.8' StrokeStartLineCap='Round' StrokeEndLineCap='Round' Visibility='Collapsed'/><Border x:Name='focus' CornerRadius='4' BorderBrush='#7C91E5' BorderThickness='2' Opacity='0'/></Grid>
  <ContentPresenter Grid.Column='1' VerticalAlignment='Center'/>
 </Grid><ControlTemplate.Triggers><Trigger Property='IsChecked' Value='True'><Setter TargetName='box' Property='Background' Value='#3659D9'/><Setter TargetName='box' Property='BorderBrush' Value='#3659D9'/><Setter TargetName='tick' Property='Visibility' Value='Visible'/></Trigger><Trigger Property='IsKeyboardFocused' Value='True'><Setter TargetName='focus' Property='Opacity' Value='1'/></Trigger><Trigger Property='IsEnabled' Value='False'><Setter Property='Opacity' Value='0.5'/><Setter Property='Cursor' Value='Arrow'/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
</Style>
<Style TargetType='ProgressBar'><Setter Property='Template'><Setter.Value><ControlTemplate TargetType='ProgressBar'><Grid><Border CornerRadius='1' Background='{TemplateBinding Background}'/><Border x:Name='pulse' CornerRadius='1' Background='{TemplateBinding Foreground}' Opacity='0.55'/></Grid><ControlTemplate.Triggers><Trigger Property='IsIndeterminate' Value='True'><Trigger.EnterActions><BeginStoryboard x:Name='activity'><Storyboard><DoubleAnimation Storyboard.TargetName='pulse' Storyboard.TargetProperty='Opacity' From='0.25' To='0.9' Duration='0:0:0.8' AutoReverse='True' RepeatBehavior='Forever'/></Storyboard></BeginStoryboard></Trigger.EnterActions><Trigger.ExitActions><RemoveStoryboard BeginStoryboardName='activity'/></Trigger.ExitActions></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
</ResourceDictionary>");
        }
    }
}
