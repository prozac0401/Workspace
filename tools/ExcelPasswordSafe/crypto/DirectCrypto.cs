using System.Security.Cryptography;
using System.Xml;
using System.Xml.Linq;
using OfficeIMO.Core.Internal;

namespace ExcelPasswordSafe.Crypto {
    public sealed class DirectCryptoResult {
        public bool Supported { get; internal set; }
        public string Status { get; internal set; } = "";
        public string Category { get; internal set; } = "";
        public string Message { get; internal set; } = "";
        public string TempHash { get; internal set; } = "";
    }

    // Uses the attributed, pinned upstream codec without rewriting workbook XML.
    // The controller owns backup, source hashes, cancellation and atomic commit.
    public static class DirectCrypto {
        public const int MaximumInputBytes = 64 * 1024 * 1024;
        private const int MaximumDescriptorBytes = 1024 * 1024;
        private static readonly byte[] CompoundMagic = { 0xd0,0xcf,0x11,0xe0,0xa1,0xb1,0x1a,0xe1 };
        private static readonly XNamespace EncryptionNs = "http://schemas.microsoft.com/office/2006/encryption";
        private static readonly XNamespace PasswordNs = "http://schemas.microsoft.com/office/2006/keyEncryptor/password";
        // Only the package, descriptor and standard Office encryption metadata
        // may be discarded/recreated by this raw-package path. Unknown outer
        // streams can contain signatures or application data and require Excel.
        private static readonly HashSet<string> KnownEncryptionStreams = new HashSet<string>(StringComparer.Ordinal) {
            "EncryptionInfo", "EncryptedPackage", "\u0006DataSpaces/Version", "\u0006DataSpaces/DataSpaceMap",
            "\u0006DataSpaces/DataSpaceInfo/StrongEncryptionDataSpace",
            "\u0006DataSpaces/TransformInfo/StrongEncryptionTransform/\u0006Primary"
        };
        private static readonly HashSet<string> KnownEncryptionStorages = new HashSet<string>(StringComparer.Ordinal) {
            "\u0006DataSpaces", "\u0006DataSpaces/DataSpaceInfo", "\u0006DataSpaces/TransformInfo",
            "\u0006DataSpaces/TransformInfo/StrongEncryptionTransform"
        };

        public static DirectCryptoResult Operate(string sourcePath, string tempPath, string extension, string mode, string oldPassword, string newPassword) {
            byte[]? source = null, plain = null, output = null, reopened = null;
            OfficeCompoundFile? compound = null;
            bool createdTemp = false, completed = false;
            DirectCryptoResult result;
            try {
                extension = (extension ?? "").ToLowerInvariant();
                if (extension != ".xlsx" && extension != ".xlsm") return Unsupported("DirectUnsupportedFormat");
                if (mode != "Encrypt" && mode != "Decrypt" && mode != "ChangePassword") return Failed("InvalidMode");
                sourcePath = Path.GetFullPath(sourcePath);
                tempPath = Path.GetFullPath(tempPath);
                if (String.Equals(sourcePath, tempPath, StringComparison.OrdinalIgnoreCase) || File.Exists(tempPath) || Directory.Exists(tempPath))
                    return Failed("InvalidTemporaryPath");
                using (var input = new FileStream(sourcePath, FileMode.Open, FileAccess.Read, FileShare.Read)) {
                    if (input.Length > MaximumInputBytes) return Unsupported("DirectUnsupportedSize");
                    source = new byte[checked((int)input.Length)];
                    int offset = 0;
                    while (offset < source.Length) {
                        int read = input.Read(source, offset, source.Length - offset);
                        if (read == 0) throw new InvalidDataException();
                        offset += read;
                    }
                    if (input.ReadByte() != -1) throw new InvalidDataException();
                }
                if (HasPrefix(source, CompoundMagic)) {
                    var options = new OfficeCompoundReadOptions(maxDirectoryEntries:4096, maxStreamCount:256,
                        maxStreamBytes:MaximumInputBytes, maxTotalStreamBytes:MaximumInputBytes);
                    if (!OfficeCompoundFileReader.TryRead(source, options, out compound, out string? error) || compound == null)
                        return Failed("InvalidPackage");
                    bool hasInfo = compound.Streams.TryGetValue("EncryptionInfo", out byte[]? info);
                    bool hasPayload = compound.Streams.TryGetValue("EncryptedPackage", out byte[]? payload);
                    if (!hasInfo && !hasPayload) return Unsupported("DirectUnsupportedContainer");
                    if (!hasInfo || !hasPayload || info == null || payload == null) return Failed("InvalidPackage");
                    if (mode == "Encrypt") return Skipped("AlreadyEncrypted");
                    if (compound.Streams.Keys.Any(path => !KnownEncryptionStreams.Contains(path)) ||
                        compound.Entries.Any(entry => !entry.IsFallback && entry.IsStorage &&
                            !KnownEncryptionStorages.Contains(entry.Path)))
                        return Unsupported("DirectUnsupportedContainer");
                    string? unsupported = ValidateDescriptor(info, payload);
                    if (unsupported != null) return Unsupported(unsupported);
                    if (String.IsNullOrEmpty(oldPassword)) return Failed("CurrentPasswordRequired");
                    // The pinned codec verifies HMAC before producing plaintext.
                    plain = OfficeEncryption.DecryptPackage(source, oldPassword, CancellationToken.None, MaximumInputBytes);
                } else {
                    if (!HasZipHeader(source)) return Failed("InvalidPackage");
                    plain = source;
                }

                string? guard = PackageGuard.Validate(plain, extension);
                if (!String.IsNullOrEmpty(guard)) {
                    if (guard == "PackageResourceLimit") return Unsupported("DirectUnsupportedSize");
                    if (guard == "SignedWorkbookUnsupported" || guard == "SharedWorkbookUnsupported" || guard == "WriteReservedUnsupported")
                        return Skipped(guard!);
                    return Failed(guard!);
                }
                if (compound == null && mode != "Encrypt") return Skipped("AlreadyUnencrypted");
                if (mode == "Decrypt") {
                    output = plain;
                } else {
                    if (String.IsNullOrEmpty(newPassword) || newPassword.Length > 15) return Failed("NewPasswordLength");
                    if (mode == "ChangePassword" && String.Equals(oldPassword,newPassword,StringComparison.Ordinal))
                        return Failed("PasswordUnchanged");
                    output = OfficeEncryption.EncryptPackage(plain, newPassword);
                    reopened = OfficeEncryption.DecryptPackage(output, newPassword, CancellationToken.None, MaximumInputBytes);
                    if (!EqualBytes(plain,reopened)) return Failed("ValidationFailed");
                    RejectPassword(output, newPassword == "EPS-Wrong-42!" ? "EPS-Wrong-43!" : "EPS-Wrong-42!");
                    if (mode == "ChangePassword") RejectPassword(output, oldPassword);
                }

                // Pin validated memory bytes, then verify the persisted bytes while
                // holding an exclusive handle. Return this hash, never a later read.
                string expectedHash = Sha(output);
                using (var file = new FileStream(tempPath,FileMode.CreateNew,FileAccess.ReadWrite,FileShare.None)) {
                    createdTemp = true;
                    file.Write(output,0,output.Length); file.Flush(true); file.Position=0;
                    using (var sha=SHA256.Create()) {
                        string persistedHash=Hex(sha.ComputeHash(file));
                        if (!String.Equals(persistedHash,expectedHash,StringComparison.Ordinal)) throw new InvalidDataException();
                    }
                }
                completed=true;
                return new DirectCryptoResult { Supported=true,Status="Validated",Category="Validated",Message="Validated",TempHash=expectedHash };
            } catch (UnauthorizedAccessException) {
                result=Failed("AccessDenied");
            } catch (CryptographicException error) {
                result=Failed(error.Message == "The encrypted package integrity check failed." ? "IntegrityCheckFailed" :
                    error.Message == "The password is incorrect." ? "OpenFailedPossiblePasswordOrCorruption" : "InvalidPackage");
            } catch (InvalidDataException) {
                result=Failed("InvalidPackage");
            } catch (IOException error) {
                int code=error.HResult & 0xffff;
                result=Failed(code==32 || code==33 ? "FileInUse" : "DirectIoFailed");
            } catch (Exception) {
                result=Failed("InvalidPackage");
            } finally {
                Clear(source); Clear(plain); Clear(output); Clear(reopened);
                if (compound != null) foreach (byte[] bytes in compound.Streams.Values) Clear(bytes);
                if (createdTemp && !completed) {
                    // This invocation alone created the output. The controller
                    // also checks cleanup; never touch a pre-existing destination.
                    try { File.Delete(tempPath); } catch { }
                }
            }
            if (createdTemp && File.Exists(tempPath)) result.Message="TemporaryCleanupIncomplete";
            return result;
        }

        private static void RejectPassword(byte[] encrypted, string password) {
            byte[]? unexpected=null;
            try {
                unexpected=OfficeEncryption.DecryptPackage(encrypted,password,CancellationToken.None,MaximumInputBytes);
            } catch (CryptographicException error) {
                if (error.Message == "The password is incorrect.") return;
                throw;
            } finally { Clear(unexpected); }
            throw new InvalidDataException();
        }
        private static DirectCryptoResult Unsupported(string category) { return new DirectCryptoResult {Supported=false,Status="Unsupported",Category=category,Message=category}; }
        private static DirectCryptoResult Failed(string category) { return new DirectCryptoResult {Supported=true,Status="Failed",Category=category,Message=category}; }
        private static DirectCryptoResult Skipped(string category) { return new DirectCryptoResult {Supported=true,Status="Skipped",Category=category,Message=category}; }
        private static void Clear(byte[]? value) { if(value!=null) Array.Clear(value,0,value.Length); }
        private static string Hex(byte[] value) { return BitConverter.ToString(value).Replace("-",""); }
        private static string Sha(byte[] value) { using(var hash=SHA256.Create()) return Hex(hash.ComputeHash(value)); }
        private static bool EqualBytes(byte[] first,byte[] second) {
            if(first.Length!=second.Length)return false;
            int different=0;for(int i=0;i<first.Length;i++)different|=first[i]^second[i];return different==0;
        }
        private static bool HasPrefix(byte[] value,byte[] prefix) {
            if(value.Length<prefix.Length)return false;
            for(int i=0;i<prefix.Length;i++)if(value[i]!=prefix[i])return false;return true;
        }
        private static bool HasZipHeader(byte[] bytes) {
            return bytes.Length>=4 && bytes[0]==0x50 && bytes[1]==0x4b &&
                ((bytes[2]==3 && bytes[3]==4)||(bytes[2]==5 && bytes[3]==6));
        }

        private static string? ValidateDescriptor(byte[] info,byte[] payload) {
            if(info.Length<8 || info.Length>MaximumDescriptorBytes || payload.Length<8) throw new InvalidDataException();
            if(info[0]!=4 || info[1]!=0 || info[2]!=4 || info[3]!=0) return "DirectUnsupportedEncryption";
            if(BitConverter.ToUInt32(info,4)!=0x40) throw new InvalidDataException();
            XDocument doc;
            var settings=new XmlReaderSettings { DtdProcessing=DtdProcessing.Prohibit,XmlResolver=null,MaxCharactersInDocument=MaximumDescriptorBytes,MaxCharactersFromEntities=0 };
            using(var input=new MemoryStream(info,8,info.Length-8,false))
            using(var reader=XmlReader.Create(input,settings)) doc=XDocument.Load(reader,LoadOptions.None);
            if(doc.Root==null || doc.Root.Name!=EncryptionNs+"encryption")throw new InvalidDataException();
            XElement keyData=One(doc.Root,EncryptionNs+"keyData");
            XElement integrity=One(doc.Root,EncryptionNs+"dataIntegrity");
            XElement encryptors=One(doc.Root,EncryptionNs+"keyEncryptors");
            if(doc.Root.Elements().Any(e=>e!=keyData && e!=integrity && e!=encryptors) ||
                keyData.HasElements || integrity.HasElements) return "DirectUnsupportedEncryption";
            XElement[] recipients=encryptors.Elements().ToArray();
            if(recipients.Length!=1 || recipients[0].Name!=EncryptionNs+"keyEncryptor" ||
                (string?)recipients[0].Attribute("uri")!="http://schemas.microsoft.com/office/2006/keyEncryptor/password")
                return "DirectUnsupportedEncryption";
            XElement[] passwordKeys=recipients[0].Elements().ToArray();
            if(passwordKeys.Length!=1 || passwordKeys[0].Name!=PasswordNs+"encryptedKey" || passwordKeys[0].HasElements)
                return "DirectUnsupportedEncryption";
            XElement passwordKey=passwordKeys[0];
            foreach(XElement node in new[]{keyData,passwordKey}) {
                if(Attr(node,"cipherAlgorithm")!="AES" || Attr(node,"cipherChaining")!="ChainingModeCBC")
                    return "DirectUnsupportedAlgorithm";
                if(Number(node,"blockSize")!=16) return "DirectUnsupportedAlgorithm";
                int bits=Number(node,"keyBits");
                if(bits!=128 && bits!=192 && bits!=256)return "DirectUnsupportedAlgorithm";
                string hash=Attr(node,"hashAlgorithm");
                if(hash!="SHA256" && hash!="SHA512")return "DirectUnsupportedAlgorithm";
                int expected=hash=="SHA256"?32:64;
                if(Number(node,"hashSize")!=expected)throw new InvalidDataException();
                if(Number(node,"saltSize")!=16)return "DirectUnsupportedAlgorithm";
                RequireLength(node,"saltValue",16);
            }
            int spin=Number(passwordKey,"spinCount");
            if(spin<=0)throw new InvalidDataException();
            if(spin>1000000)return "DirectUnsupportedParameters";
            RequireLength(passwordKey,"encryptedVerifierHashInput",16);
            RequireLength(passwordKey,"encryptedVerifierHashValue",Number(passwordKey,"hashSize"));
            int secretBytes=Number(keyData,"keyBits")/8;
            RequireLength(passwordKey,"encryptedKeyValue",((secretBytes+15)/16)*16);
            int hashBytes=Number(keyData,"hashSize");
            RequireLength(integrity,"encryptedHmacValue",hashBytes);
            byte[] hmacKey=Base64(integrity,"encryptedHmacKey");
            if(hmacKey.Length!=16 && hmacKey.Length!=hashBytes)throw new InvalidDataException();
            ulong originalSize=BitConverter.ToUInt64(payload,0);
            if(originalSize>MaximumInputBytes)return "DirectUnsupportedSize";
            ulong expectedPayload=8+((originalSize+15)/16)*16;
            if((ulong)payload.Length!=expectedPayload)throw new InvalidDataException();
            return null;
        }
        private static XElement One(XElement parent,XName name) {
            XElement[] elements=parent.Elements(name).ToArray();if(elements.Length!=1)throw new InvalidDataException();return elements[0];
        }
        private static string Attr(XElement node,string name) {
            string? value=(string?)node.Attribute(name);if(String.IsNullOrEmpty(value))throw new InvalidDataException();return value!;
        }
        private static int Number(XElement node,string name) {
            if(!Int32.TryParse(Attr(node,name),System.Globalization.NumberStyles.None,System.Globalization.CultureInfo.InvariantCulture,out int value))throw new InvalidDataException();
            return value;
        }
        private static byte[] Base64(XElement node,string name) {
            try{return Convert.FromBase64String(Attr(node,name));}catch(FormatException){throw new InvalidDataException();}
        }
        private static void RequireLength(XElement node,string name,int expected) {
            if(Base64(node,name).Length!=expected)throw new InvalidDataException();
        }
    }
}

