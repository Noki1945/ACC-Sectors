using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace AccOverlay {
 public sealed class DeltaGraphSegment {
  public readonly double X1,Y1,X2,Y2;
  public DeltaGraphSegment(double x1,double y1,double x2,double y2) { X1=x1;Y1=y1;X2=x2;Y2=y2; }
 }
 public sealed class DeltaGraphData {
  public readonly DeltaGraphSegment[] Segments;
  public readonly int? FinalDelta;
  public readonly ComparisonMode ReferenceMode;
  public readonly bool CompleteLap, Estimated;
  DeltaGraphData(DeltaGraphSegment[] segments,int? finalDelta,ComparisonMode mode,bool estimated) { Segments=segments; FinalDelta=finalDelta; ReferenceMode=mode; CompleteLap=true; Estimated=estimated; }
  public static DeltaGraphData Build(bool complete,float[] positions,int[] times,int total,float[] referencePositions,int[] referenceTimes,int referenceTotal,ComparisonMode mode,bool estimated) {
   if(!complete) return null;
   int? final=total>0 && referenceTotal>0?(int?)(total-referenceTotal):null;
   List<DeltaGraphSegment> segments=new List<DeltaGraphSegment>();
   if(ValidTrace(positions,times) && ValidTrace(referencePositions,referenceTimes)) {
    double lastX=0,lastDelta=0,lastReferenceTime=0; int lastTime=0; bool haveLast=false;
    for(int i=0;i<positions.Length;i++) {
     double referenceTime;
     if(!Interpolate(referencePositions,referenceTimes,positions[i],out referenceTime)) { haveLast=false; continue; }
     double delta=(times[i]-referenceTime)/1000.0;
     if(haveLast && times[i]-lastTime<=2000 && referenceTime-lastReferenceTime<=2000 && positions[i]-lastX<=0.05) segments.Add(new DeltaGraphSegment(lastX,lastDelta,positions[i],delta));
     lastX=positions[i];lastDelta=delta;lastReferenceTime=referenceTime;lastTime=times[i];haveLast=true;
    }
   }
   return new DeltaGraphData(segments.Count>=2?segments.ToArray():new DeltaGraphSegment[0],final,mode,estimated);
  }
  static bool ValidTrace(float[] positions,int[] times) {
   // A completed reference lap may have been recorded from the pit exit or
   // after the overlay started. Use its actual overlapping range rather than
   // rejecting all known samples for missing start/end points. Interpolate
   // still refuses extrapolation and large gaps.
   if(positions==null || times==null || positions.Length!=times.Length || positions.Length<3) return false;
   for(int i=0;i<positions.Length;i++) {
    if(float.IsNaN(positions[i]) || float.IsInfinity(positions[i]) || positions[i]<0 || positions[i]>1 || times[i]<0) return false;
    if(i>0 && (positions[i]<=positions[i-1] || times[i]<=times[i-1])) return false;
   }
   return true;
  }
  static bool Interpolate(float[] positions,int[] times,float progress,out double time) {
   time=0; int index=Array.BinarySearch(positions,progress);
   if(index>=0) { time=times[index]; return true; }
   index=~index; if(index<=0 || index>=positions.Length) return false;
   double span=positions[index]-positions[index-1]; int gap=times[index]-times[index-1];
   if(span<=0 || span>0.05 || gap<=0 || gap>2000) return false;
   time=times[index-1]+gap*(progress-positions[index-1])/span; return true;
  }
 }
 public sealed class DeltaGraphPlacement {
  public double Left,Top,Width,Height; public bool Visible,OnLeft;
 }
 public static class DeltaGraphLayout {
  public static bool ShouldShow(bool enabled,bool holding,DeltaGraphData graph) { return enabled && holding && graph!=null && graph.CompleteLap; }
  public static DeltaGraphPlacement Place(double left,double top,double width,double height,double screenLeft,double screenTop,double screenWidth,double screenHeight) {
   DeltaGraphPlacement result=new DeltaGraphPlacement { Width=230,Height=Math.Min(height*0.4,screenHeight) };
   if(width<=0 || height<=0 || screenWidth<=0 || screenHeight<=0) return result;
   double right=left+width+6, alternative=left-6-result.Width;
   if(right+result.Width<=screenLeft+screenWidth && right>=screenLeft) result.Left=right;
   else if(alternative>=screenLeft && alternative+result.Width<=screenLeft+screenWidth) { result.Left=alternative;result.OnLeft=true; }
   else return result;
   result.Top=Math.Max(screenTop,Math.Min(top+(height-result.Height)/2,screenTop+screenHeight-result.Height));
   result.Visible=true; return result;
  }
 }
 public sealed class DeltaGraphPlot {
  public string Green,Red,Neutral;
  public double ScaleSeconds;
  static string N(double value) { return value.ToString("0.###",CultureInfo.InvariantCulture); }
  static void Add(StringBuilder builder,double x1,double y1,double x2,double y2,double width,double height,double scale) { builder.Append("M ").Append(N(x1*width)).Append(',').Append(N(height/2-y1/scale*height/2)).Append(" L ").Append(N(x2*width)).Append(',').Append(N(height/2-y2/scale*height/2)).Append(' '); }
  public static DeltaGraphPlot Create(DeltaGraphData data,double width,double height) {
   DeltaGraphPlot plot=new DeltaGraphPlot(); double max=0;
   foreach(DeltaGraphSegment s in data.Segments) max=Math.Max(max,Math.Max(Math.Abs(s.Y1),Math.Abs(s.Y2)));
   plot.ScaleSeconds=Math.Max(0.1,max*1.12);
   StringBuilder green=new StringBuilder(),red=new StringBuilder(),neutral=new StringBuilder();
   foreach(DeltaGraphSegment s in data.Segments) {
    if(s.Y1*s.Y2<0) {
     double cross=s.X1+(s.X2-s.X1)*(-s.Y1)/(s.Y2-s.Y1);
     Add(s.Y1<0?green:red,s.X1,s.Y1,cross,0,width,height,plot.ScaleSeconds);
     Add(s.Y2<0?green:red,cross,0,s.X2,s.Y2,width,height,plot.ScaleSeconds);
    } else Add((s.Y1+s.Y2)<0?green:((s.Y1+s.Y2)>0?red:neutral),s.X1,s.Y1,s.X2,s.Y2,width,height,plot.ScaleSeconds);
   }
   plot.Green=green.ToString();plot.Red=red.ToString();plot.Neutral=neutral.ToString();return plot;
  }
 }
}
