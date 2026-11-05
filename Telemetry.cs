using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Text;

namespace AccOverlay {
 public sealed class Frame {
  public int Packet, Status, Session, Laps, Current, Last, Best, Sector, Split;
  public float Remaining, Position;
  public int SessionIndex;
  public bool Valid=true;
 }
 public sealed class Reader : IDisposable {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenFileMapping(uint access, bool inherit, string name);
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr MapViewOfFile(IntPtr handle,uint access,uint hi,uint lo,UIntPtr size);
  [DllImport("kernel32.dll")] static extern bool UnmapViewOfFile(IntPtr p);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr p);
  IntPtr handle, view;
  public Frame Read() {
   if(view==IntPtr.Zero) {
    handle=OpenFileMapping(4,false,"Local\\acpmf_graphics");
    if(handle==IntPtr.Zero) return null;
    view=MapViewOfFile(handle,4,0,0,new UIntPtr(1412));
    if(view==IntPtr.Zero) { Dispose(); return null; }
   }
   byte[] b=new byte[1412];
   for(int retry=0;retry<3;retry++) {
    int packet=Marshal.ReadInt32(view);
    Marshal.Copy(view,b,0,b.Length);
    if(packet!=Marshal.ReadInt32(view)) continue;
    return Decode(b);
   }
   return null;
  }
  public static Frame Decode(byte[] b) {
   if(b==null || b.Length<1412) throw new ArgumentException("Incomplete ACC graphics page");
   int best=BitConverter.ToInt32(b,148);
   if(best<=0 || best==int.MaxValue) best=ParseTime(Encoding.Unicode.GetString(b,72,30).TrimEnd('\0'));
   return new Frame { Packet=BitConverter.ToInt32(b,0),Status=BitConverter.ToInt32(b,4),Session=BitConverter.ToInt32(b,8),Laps=BitConverter.ToInt32(b,132),Current=BitConverter.ToInt32(b,140),Last=BitConverter.ToInt32(b,144),Best=best,Remaining=BitConverter.ToSingle(b,152),Sector=BitConverter.ToInt32(b,164),Split=BitConverter.ToInt32(b,168),Position=BitConverter.ToSingle(b,248),SessionIndex=BitConverter.ToInt32(b,1320),Valid=BitConverter.ToInt32(b,1408)!=0 };
  }
  public static int ParseTime(string text) {
   TimeSpan value;
   return TimeSpan.TryParseExact(text,new string[]{@"m\:ss\.fff",@"mm\:ss\.fff",@"m\:ss\:fff",@"mm\:ss\:fff"},CultureInfo.InvariantCulture,out value) && value.TotalMilliseconds>0 && value.TotalMilliseconds<int.MaxValue?(int)value.TotalMilliseconds:0;
  }
  public void Dispose() { if(view!=IntPtr.Zero) UnmapViewOfFile(view); if(handle!=IntPtr.Zero) CloseHandle(handle); view=handle=IntPtr.Zero; }
 }
 public sealed class Timing {
  public int[] Sectors=new int[3], Previous=new int[3];
  public int?[] Differences=new int?[3];
  public int? LapDifference;
  public int Laps, Best, LastLap;
  public bool BestIsObserved;
  int officialBest, observedBest;
  Frame prior;
  int previousLap;
  int[] lapSectors=new int[3];
  int[] pendingSectors;
  int pendingLast;
  bool pendingFull, pendingValid;
  int pendingSector;
  int splitBeforeBoundary;
  int[] completedDisplay;
  int?[] completedDifferences;
  long holdUntil;
  long wrapWaitSince=-1;
  bool lapValid=true;
  List<float> positions=new List<float>(); List<int> times=new List<int>();
  float[] referencePositions=new float[0]; int[] referenceTimes=new int[0];
  bool fullLap;
  public int? LiveDifference;
  public bool HasReference { get { return referencePositions.Length>1; } }
  public void Reset() { Sectors=new int[3]; Previous=new int[3]; Differences=new int?[3]; lapSectors=new int[3]; pendingSectors=completedDisplay=null; completedDifferences=null; holdUntil=0; wrapWaitSince=-1; pendingSector=0; LapDifference=LiveDifference=null; Laps=Best=LastLap=previousLap=officialBest=observedBest=0; BestIsObserved=false; lapValid=true; prior=null; positions.Clear(); times.Clear(); referencePositions=new float[0]; referenceTimes=new int[0]; fullLap=false; }
  void Record(int index,int value) { if(value<=0) return; Sectors[index]=value; Differences[index]=Previous[index]>0?(int?)(value-Previous[index]):null; }
  static long ClockMs() { return (long)(Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency); }
  public void Update(Frame f) { Update(f,ClockMs()); }
  public void Update(Frame f,long now) {
   if(f.Status==0) { Reset(); return; }
   if(f.Status==1) { Reset(); return; }
   if(prior!=null && (f.Session!=prior.Session || f.SessionIndex!=prior.SessionIndex || f.Laps<prior.Laps || f.Remaining>prior.Remaining+5)) Reset();
   // Position/clock can wrap a packet before the completed-lap counter does.
   if(prior!=null && f.Laps==prior.Laps && prior.Position>0.98f && f.Position<0.02f) {
    if(wrapWaitSince<0) wrapWaitSince=now;
    if(now-wrapWaitSince<1000) return;
   } else wrapWaitSince=-1;
   Laps=f.Laps; LastLap=f.Last>0?f.Last:0;
   if(f.Best>0 && f.Best<int.MaxValue) officialBest=f.Best;
   if(prior!=null && f.Laps==prior.Laps && f.Current+1000<prior.Current) {
    // A return to the garage/restart is not a completed lap.
    lapSectors=new int[3]; Sectors=new int[3]; Differences=new int?[3];
    pendingSector=0; pendingSectors=completedDisplay=null; holdUntil=0;
    positions.Clear(); times.Clear(); referencePositions=new float[0]; referenceTimes=new int[0];
    fullLap=false; lapValid=f.Valid; LiveDifference=null; prior=null;
   }
   if(prior!=null) {
    if(f.Laps==prior.Laps+1) {
     if(positions.Count>1) { referencePositions=positions.ToArray(); referenceTimes=times.ToArray(); }
     else { referencePositions=new float[0]; referenceTimes=new int[0]; }
     positions.Clear(); times.Clear(); positions.Add(0); times.Add(0);
     pendingFull=fullLap; pendingValid=lapValid; fullLap=true;
     pendingSectors=(int[])lapSectors.Clone(); pendingLast=prior.Last;
     holdUntil=now+5000;
     lapSectors=new int[3]; pendingSector=0;
    } else if(f.Laps>prior.Laps+1) { Previous=new int[3]; Sectors=new int[3]; lapSectors=new int[3]; pendingSectors=null; pendingSector=0; Differences=new int?[3]; previousLap=f.Last; LapDifference=null; }
    else if(f.Sector!=prior.Sector && f.Sector>0 && f.Sector<=2 && f.Sector==prior.Sector+1) {
     if(f.Sector==1) { Sectors=new int[3]; Differences=new int?[3]; }
     pendingSector=f.Sector; splitBeforeBoundary=prior.Split;
    }
   } else {
    previousLap=f.Last>0?f.Last:0;
    if(observedBest==0 || (previousLap>0 && previousLap<observedBest)) observedBest=previousLap;
    fullLap=f.Current<=1000 && f.Sector==0 && f.Position<0.01f;
    if(fullLap) { positions.Add(0); times.Add(0); }
    if(f.Sector==1 && f.Split>0 && f.Split<=f.Current) { lapSectors[0]=f.Split; Record(0,f.Split); }
   }
   // ACC publishes cumulative split times; wait if the split lags the sector index.
   if(pendingSector==f.Sector && pendingSector>0 && f.Split>0 && f.Split!=splitBeforeBoundary && (f.Current==0 || f.Split<=f.Current)) {
    if(pendingSector==1) { lapSectors[0]=f.Split; Record(0,f.Split); }
    else if(lapSectors[0]>0 && f.Split>lapSectors[0]) { lapSectors[1]=f.Split-lapSectors[0]; Record(1,lapSectors[1]); }
    pendingSector=0;
   }
   // The lap counter can arrive before the final lap time.
   if(pendingSectors!=null && f.Last>0 && (f.Last!=pendingLast || f.Current>=300)) {
    Sectors=(int[])pendingSectors.Clone();
    if(Sectors[0]>0 && Sectors[1]>0) Record(2,f.Last-Sectors[0]-Sectors[1]);
    LapDifference=previousLap>0?(int?)(f.Last-previousLap):null;
    if(observedBest==0 || f.Last<observedBest) observedBest=f.Last;
    // Official ACC best remains authoritative. Only locally recorded valid, full
    // laps may fill in while the game has not published its best yet.
    if(pendingFull && pendingValid && (officialBest==0 || f.Last<officialBest)) officialBest=f.Last;
    if(referencePositions.Length>0 && referencePositions[referencePositions.Length-1]<1 && f.Last>referenceTimes[referenceTimes.Length-1]) {
     int length=referencePositions.Length; Array.Resize(ref referencePositions,length+1); Array.Resize(ref referenceTimes,length+1); referencePositions[length]=1; referenceTimes[length]=f.Last;
    }
    completedDisplay=(int[])Sectors.Clone(); completedDifferences=(int?[])Differences.Clone();
    previousLap=f.Last; Previous=(int[])Sectors.Clone(); pendingSectors=null;
    lapValid=f.Valid;
   }
   Best=officialBest>0?officialBest:observedBest; BestIsObserved=officialBest==0 && observedBest>0;
   LiveDifference=null;
   if(f.Position>=0 && f.Position<=1 && f.Current>=0) {
    int index=Array.BinarySearch(referencePositions,f.Position);
    if(index>=0) LiveDifference=f.Current-referenceTimes[index];
    else { index=~index;
    if(index>0 && index<referencePositions.Length) {
     float span=referencePositions[index]-referencePositions[index-1];
     if(span>0 && referenceTimes[index]-referenceTimes[index-1]<=2000) LiveDifference=f.Current-(int)(referenceTimes[index-1]+(referenceTimes[index]-referenceTimes[index-1])*(f.Position-referencePositions[index-1])/span);
    }
    }
    if(positions.Count==0 || (f.Position>positions[positions.Count-1]+0.0001f && f.Current>times[times.Count-1])) { positions.Add(f.Position); times.Add(f.Current); }
    else if(positions.Count>0 && f.Position<positions[positions.Count-1]-0.02f) { fullLap=false; positions.Clear(); times.Clear(); referencePositions=new float[0]; referenceTimes=new int[0]; }
   }
   lapValid=lapValid && f.Valid;
   prior=f;
  }
  public Display GetDisplay() { return GetDisplay(ClockMs()); }
  public Display GetDisplay(long now) {
   Display d=new Display();
   if(prior==null) return d;
   d.Holding=completedDisplay!=null && now<holdUntil;
   if(d.Holding) { d.Sectors=(int[])completedDisplay.Clone(); d.Differences=(int?[])completedDifferences.Clone(); d.Lap=LastLap; d.LapDelta=LapDifference; return d; }
   d.Sectors=(int[])lapSectors.Clone();
   for(int i=0;i<3;i++) if(d.Sectors[i]>0 && Previous[i]>0) d.Differences[i]=d.Sectors[i]-Previous[i];
   int sector=prior.Sector;
   if(sector>=0 && sector<3) {
    int elapsed=0; bool known=true;
    for(int i=0;i<sector;i++) { if(lapSectors[i]<=0) known=false; elapsed+=lapSectors[i]; }
    // S3 can be timed from its cumulative boundary even on a partial recording.
    if(!known && sector==2 && prior.Split>0 && prior.Split<=prior.Current) { elapsed=prior.Split; known=true; }
    if(known) { d.Sectors[sector]=Math.Max(0,prior.Current-elapsed); d.ActiveSector=sector; }
   }
   d.Lap=prior.Current; d.LapDelta=LiveDifference;
   return d;
  }
  public static string Time(int ms) { return ms<=0?"--:--.---":string.Format("{0}:{1:00}.{2:000}",ms/60000,(ms/1000)%60,ms%1000); }
  public static string Delta(int? ms) { return ms.HasValue?string.Format(System.Globalization.CultureInfo.InvariantCulture,"{0:+0.000;-0.000;0.000}",ms.Value/1000.0):"—"; }
 }
 public sealed class Display {
  public int[] Sectors=new int[3];
  public int?[] Differences=new int?[3];
  public int Lap, ActiveSector=-1;
  public int? LapDelta;
  public bool Holding;
 }
}
