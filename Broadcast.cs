using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace AccOverlay {
 // Minimal subscription to Kunos Broadcasting protocol v4. Never sends driving,
 // camera, replay, or HUD commands. All traffic goes to the local ACC client.
 public sealed class Broadcast : IDisposable {
  UdpClient socket;
  readonly int port;
  readonly string password;
  DateTime retryAt=DateTime.MinValue, lastUpdate=DateTime.MinValue;
  bool registered;
  int sessionKey=-1;
  public int Best { get; private set; }
  public string Status { get; private set; }
  public Broadcast(int port,string password) { this.port=port; this.password=password ?? ""; Status="Ожидание ACC"; }
  static void WriteString(BinaryWriter writer,string value) { byte[] data=Encoding.UTF8.GetBytes(value); writer.Write((ushort)data.Length); writer.Write(data); }
  static string ReadString(BinaryReader reader) { int length=reader.ReadUInt16(); byte[] bytes=reader.ReadBytes(length); if(bytes.Length!=length) throw new EndOfStreamException(); return Encoding.UTF8.GetString(bytes); }
  void Register() {
   if(socket==null) { socket=new UdpClient(new IPEndPoint(IPAddress.Loopback,0)); socket.Connect(IPAddress.Loopback,port); }
   using(MemoryStream stream=new MemoryStream()) using(BinaryWriter writer=new BinaryWriter(stream)) {
    writer.Write((byte)1); writer.Write((byte)4); WriteString(writer,"ACC Sectors"); WriteString(writer,password); writer.Write(250); WriteString(writer,"");
    byte[] data=stream.ToArray(); socket.Send(data,data.Length);
   }
  }
  public void Poll() {
   if(port<=0 || port>65535) return;
   try {
    if(DateTime.UtcNow>=retryAt && (!registered || (DateTime.UtcNow-lastUpdate).TotalSeconds>10)) { registered=false; retryAt=DateTime.UtcNow.AddSeconds(3); Register(); }
    for(int i=0;socket!=null && i<64 && socket.Available>0;i++) {
     IPEndPoint sender=new IPEndPoint(IPAddress.Any,0);
     byte[] packet=socket.Receive(ref sender);
     try { Process(packet); } catch(EndOfStreamException) { Status="Неполный пакет ACC"; } catch(IOException) { Status="Ошибка пакета ACC"; }
    }
   } catch(SocketException) { registered=false; Status="Ожидание ACC / перезапустите игру после включения телеметрии"; if(socket!=null) socket.Close(); socket=null; }
  }
  public void Process(byte[] packet) {
   using(BinaryReader reader=new BinaryReader(new MemoryStream(packet))) {
    byte type=reader.ReadByte();
    if(type==1) {
     reader.ReadInt32(); registered=reader.ReadByte()!=0; reader.ReadByte(); ReadString(reader);
     Status=registered?"Подключено к ACC":"ACC отклонила подключение"; lastUpdate=DateTime.UtcNow; return;
    }
    if(type!=2) return;
    int eventIndex=reader.ReadUInt16(), sessionIndex=reader.ReadUInt16();
    int key=(eventIndex<<16)|sessionIndex;
    reader.ReadByte(); reader.ReadByte(); reader.ReadSingle(); reader.ReadSingle(); reader.ReadInt32();
    ReadString(reader); ReadString(reader); ReadString(reader);
    bool replay=reader.ReadByte()!=0; if(replay) { reader.ReadSingle(); reader.ReadSingle(); }
    reader.ReadSingle(); for(int i=0;i<5;i++) reader.ReadByte();
    int time=reader.ReadInt32(); reader.ReadUInt16(); reader.ReadUInt16();
    int splits=reader.ReadByte(); for(int i=0;i<splits;i++) reader.ReadInt32();
    bool invalid=reader.ReadByte()!=0, valid=reader.ReadByte()!=0;
    reader.ReadByte(); reader.ReadByte();
    if(replay) return;
    if(key!=sessionKey) { Best=0; sessionKey=key; }
    if(time>0 && time<int.MaxValue && valid && !invalid) Best=time;
    registered=true; lastUpdate=DateTime.UtcNow; Status="Подключено к ACC";
   }
  }
  public bool Fresh { get { return registered && (DateTime.UtcNow-lastUpdate).TotalSeconds<10; } }
  public void Dispose() { if(socket!=null) { try { if(registered) socket.Send(new byte[]{9},1); } catch(SocketException) {} socket.Close(); socket=null; } }
 }
}
