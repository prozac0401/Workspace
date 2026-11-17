using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Collections.Generic;
using System.Text;
using System.Xml.Linq;
public static class CryptoFixtureTools {
    public static byte[] SmallPackage(int length) {
        var entries=new Dictionary<string,string> {
            {"[Content_Types].xml","<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>"},
            {"_rels/.rels","<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"r1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"},
            {"xl/workbook.xml","<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Data\" sheetId=\"1\" r:id=\"r1\"/></sheets></workbook>"},
            {"xl/_rels/workbook.xml.rels","<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"r1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>"},
            {"xl/worksheets/sheet1.xml","<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>synthetic</t></is></c></row></sheetData></worksheet>"}
        };
        byte[] bytes;
        using(var memory=new MemoryStream()) {
            using(var zip=new ZipArchive(memory,ZipArchiveMode.Create,true))
                foreach(var entry in entries) using(var writer=new StreamWriter(zip.CreateEntry(entry.Key).Open(),new UTF8Encoding(false)))writer.Write(entry.Value);
            bytes=memory.ToArray();
        }
        if(length==0)return bytes;
        if(length<bytes.Length || length-bytes.Length>65535)throw new Exception("Invalid synthetic ZIP target size");
        int padding=length-bytes.Length;
        bytes[bytes.Length-2]=(byte)padding;bytes[bytes.Length-1]=(byte)(padding>>8);
        Array.Resize(ref bytes,length);return bytes;
    }
    public static byte[] Mutate(Assembly assembly,byte[] encrypted,string kind) {
        const BindingFlags flags=BindingFlags.Static|BindingFlags.Public|BindingFlags.NonPublic;
        Type reader=assembly.GetType("OfficeIMO.Core.Internal.OfficeCompoundFileReader",true);
        MethodInfo read=reader.GetMethods(flags).Single(m=>m.Name=="TryRead"&&m.GetParameters().Length==3&&m.GetParameters()[1].ParameterType==typeof(Dictionary<string,byte[]>).MakeByRefType());
        object[] args={encrypted,null,null};
        if(!(bool)read.Invoke(null,args))throw new Exception("Fixture CFB could not be read");
        var streams=(Dictionary<string,byte[]>)args[1];
        byte[] info=streams["EncryptionInfo"],payload=streams["EncryptedPackage"];
        if(kind=="payload-flip"){payload[8]^=1;}
        else if(kind=="payload-truncate"){Array.Resize(ref payload,payload.Length-16);streams["EncryptedPackage"]=payload;}
        else if(kind=="length-header"){for(int i=0;i<8;i++)payload[i]=0;}
        else if(kind=="standard"){info[2]=2;}
        else if(kind=="malformed-xml"){streams["EncryptionInfo"]=info.Take(8).Concat(Encoding.UTF8.GetBytes("<")).ToArray();}
        else if(kind=="unknown-outer-stream"){streams["CustomBusinessData"]=Encoding.UTF8.GetBytes("synthetic metadata");}
        else if(kind=="outer-signature-stream"){streams["\u0005DigitalSignature"]=Encoding.UTF8.GetBytes("synthetic signature, not a real signature");}
        else if(kind=="unknown-dataspace-stream"){streams["\u0006DataSpaces/CustomMetadata"]=Encoding.UTF8.GetBytes("synthetic metadata");}
        else {
            XDocument doc=XDocument.Parse(Encoding.UTF8.GetString(info,8,info.Length-8));
            XNamespace e="http://schemas.microsoft.com/office/2006/encryption",p="http://schemas.microsoft.com/office/2006/keyEncryptor/password";
            if(kind=="missing-hmac")doc.Root.Element(e+"dataIntegrity").Remove();
            else if(kind=="hmac-flip"){
                var attr=doc.Root.Element(e+"dataIntegrity").Attribute("encryptedHmacValue");byte[] value=Convert.FromBase64String(attr.Value);value[0]^=1;attr.Value=Convert.ToBase64String(value);
            } else if(kind=="unsupported-algorithm")doc.Root.Element(e+"keyData").SetAttributeValue("cipherAlgorithm","RC4");
            else if(kind=="invalid-hash-size")doc.Root.Element(e+"keyData").SetAttributeValue("hashSize","0");
            else if(kind=="spin-limit")doc.Descendants(p+"encryptedKey").Single().SetAttributeValue("spinCount","1000001");
            else if(kind=="additional-certificate")doc.Root.Element(e+"keyEncryptors").Add(
                new XElement(e+"keyEncryptor",new XAttribute("uri","http://schemas.microsoft.com/office/2006/keyEncryptor/certificate"),
                    new XElement(XName.Get("encryptedKey","http://schemas.microsoft.com/office/2006/keyEncryptor/certificate"),
                        new XAttribute("encryptedKeyValue","AA=="))));
            else if(kind=="multiple-password-keys"){
                XElement key=doc.Descendants(p+"encryptedKey").Single();key.Parent.Add(new XElement(key));
            }
            else if(kind=="unknown-recipients-child")doc.Root.Element(e+"keyEncryptors").Add(new XElement(e+"extension"));
            else if(kind=="unknown-recipient-child")doc.Descendants(p+"encryptedKey").Single().Parent.Add(new XElement(e+"extension"));
            else if(kind=="unknown-descriptor-child")doc.Root.Add(new XElement(e+"extension"));
            else throw new Exception("Unknown fixture mutation");
            streams["EncryptionInfo"]=info.Take(8).Concat(Encoding.UTF8.GetBytes(doc.ToString(SaveOptions.DisableFormatting))).ToArray();
        }
        Type streamType=assembly.GetType("OfficeIMO.Core.Internal.OfficeCompoundStream",true);
        ConstructorInfo constructor=streamType.GetConstructor(BindingFlags.Instance|BindingFlags.NonPublic,null,new[]{typeof(string),typeof(byte[])},null);
        Array values=Array.CreateInstance(streamType,streams.Count);int n=0;
        foreach(var pair in streams)values.SetValue(constructor.Invoke(new object[]{pair.Key,pair.Value}),n++);
        Type writer=assembly.GetType("OfficeIMO.Core.Internal.OfficeCompoundFileWriter",true);
        MethodInfo write=writer.GetMethods(flags).Single(m=>m.Name=="Write"&&m.GetParameters().Length==2);
        return (byte[])write.Invoke(null,new object[]{values,null});
    }
}

