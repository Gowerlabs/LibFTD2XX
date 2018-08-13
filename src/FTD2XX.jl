module FTD2XX

export FT_HANDLE, createdeviceinfolist, getdeviceinfolist, listdevices, ftopen, 
       close, baudrate, status, FTOpenBy, OPEN_BY_SERIAL_NUMBER,
       OPEN_BY_DESCRIPTION, OPEN_BY_LOCATION

if is_windows()
  const lib_path =  Pkg.dir("FTD2XX") * "\\lib\\WIN\\amd64\\ftd2xx64"
else
  error("not supported on this platform")
end

const lib = Ref{Ptr{Void}}(0)

const cfuncn = [
  :FT_CreateDeviceInfoList
  :FT_GetDeviceInfoList
  :FT_Open
  :FT_Close
  :FT_Read
  :FT_Write
  :FT_SetBaudRate
  :FT_GetModemStatus
  :FT_GetQueueStatus
  :FT_OpenEx
  :FT_Purge
  ]

const cfunc = Dict{Symbol, Ptr{Void}}()

function __init__()
  lib[] = Libdl.dlopen(lib_path)
  for n in cfuncn
    cfunc[n] = Libdl.dlsym(lib[], n)
  end
end

const DWORD = Cuint
const ULONG = Culong
const FT_STATUS = ULONG

mutable struct FT_HANDLE<:IO 
  p::Ptr{Void} 
end

function FT_HANDLE()
  handle = FT_HANDLE(C_NULL)
  finalizer(handle, destroy!)
  handle
end

function destroy!(handle::FT_HANDLE)
  if handle.p != C_NULL
    flush(handle)
    close(handle)
  end
  handle.p = C_NULL
end

@enum(
  FT_STATUS_ENUM,
  FT_OK,
  FT_INVALID_HANDLE,
  FT_DEVICE_NOT_FOUND,
  FT_DEVICE_NOT_OPENED,
  FT_IO_ERROR,
  FT_INSUFFICIENT_RESOURCES,
  FT_INVALID_PARAMETER,
  FT_INVALID_BAUD_RATE,
  FT_DEVICE_NOT_OPENED_FOR_ERASE,
  FT_DEVICE_NOT_OPENED_FOR_WRITE,
  FT_FAILED_TO_WRITE_DEVICE,
  FT_EEPROM_READ_FAILED,
  FT_EEPROM_WRITE_FAILED,
  FT_EEPROM_ERASE_FAILED,
  FT_EEPROM_NOT_PRESENT,
  FT_EEPROM_NOT_PROGRAMMED,
  FT_INVALID_ARGS,
  FT_NOT_SUPPORTED,
  FT_OTHER_ERROR,
  FT_DEVICE_LIST_NOT_READY,
)

include("rarelyused.jl")

@enum(
  FTOpenBy,
  OPEN_BY_SERIAL_NUMBER = FT_OPEN_BY_SERIAL_NUMBER,
  OPEN_BY_DESCRIPTION = FT_OPEN_BY_DESCRIPTION,
  OPEN_BY_LOCATION = FT_OPEN_BY_LOCATION,
)

const FT_PURGE_RX = 1
const FT_PURGE_TX = 2

struct FT_DEVICE_LIST_INFO_NODE
  flags::ULONG
  typ::ULONG
  id::ULONG
  locid::DWORD
  serialnumber::NTuple{16, Cchar}
  description::NTuple{64, Cchar}
  fthandle::Ptr{Void}
end

function Base.String(input::NTuple{N, Cchar} where N)
  if any(input .== 0)
    endidx = find(input .== 0)[1]-1
  elseif all(input .> 0)
    endidx = length(input)
  else
    throw(MethodError("No terminator or negative values!"))
  end
  String(UInt8.([char for char in input[1:endidx]]))
end

function createdeviceinfolist()
  numdevs = Ref{DWORD}(0)
  status = ccall(cfunc[:FT_CreateDeviceInfoList], cdecl, FT_STATUS, 
                 (Ref{DWORD},),
                  numdevs)
  FT_STATUS_ENUM(status) == FT_OK || throw(FT_STATUS_ENUM(status))
  numdevs[]
end

function getdeviceinfolist(numdevs)
  list  = Vector{FT_DEVICE_LIST_INFO_NODE}(numdevs)
  elnum = Ref{DWORD}(0)
  status = ccall(cfunc[:FT_GetDeviceInfoList], cdecl, FT_STATUS, 
                 (Ref{FT_DEVICE_LIST_INFO_NODE}, Ref{DWORD}),
                  list,                          elnum)
  FT_STATUS_ENUM(status) == FT_OK || throw(FT_STATUS_ENUM(status))
  list, elnum[]
end

function ftopen(devidx::Int)
  handle = FT_HANDLE()
  status = ccall(cfunc[:FT_Open], cdecl, FT_STATUS, (Int,    Ref{FT_HANDLE}),
                                                     devidx, handle)
  if FT_STATUS_ENUM(status) != FT_OK
    handle.p = C_NULL
    throw(FT_STATUS_ENUM(status))
  end
  handle
end

function Base.close(handle::FT_HANDLE)
  status = ccall(cfunc[:FT_Close], cdecl, FT_STATUS, (FT_HANDLE, ),
                                                       handle)
  FT_STATUS_ENUM(status) == FT_OK || throw(FT_STATUS_ENUM(status))
  handle.p = C_NULL
  return
end

function Base.readbytes!(handle::FT_HANDLE, b::AbstractVector{UInt8}, nb=length(b))
  nbav = nb_available(handle)
  if nbav < nb
    nb = nbav
  end
  if length(b) < nb
    resize!(b, nb)
  end
  nbrx = Ref{DWORD}()
  buffer = Vector{UInt8}(b)
  status = ccall(cfunc[:FT_Read], cdecl, FT_STATUS, 
                 (FT_HANDLE, Ptr{UInt8}, DWORD, Ref{DWORD}),
                  handle,    buffer,     nb,    nbrx)
  FT_STATUS_ENUM(status) == FT_OK || throw(FT_STATUS_ENUM(status))
  nbrx[]
end

function Base.write(handle::FT_HANDLE, buffer::Vector{UInt8})
  nb = DWORD(length(buffer))
  nbtx = Ref{DWORD}()
  status = ccall(cfunc[:FT_Write], cdecl, FT_STATUS, 
                 (FT_HANDLE, Ptr{UInt8}, DWORD, Ref{DWORD}),
                  handle,    buffer,     nb,    nbtx)
  FT_STATUS_ENUM(status) == FT_OK || throw(FT_STATUS_ENUM(status))
  nbtx[]
end

function baudrate(handle::FT_HANDLE, baud)
  status = ccall(cfunc[:FT_SetBaudRate], cdecl, FT_STATUS, 
                 (FT_HANDLE, DWORD),
                  handle,    DWORD(baud))
  FT_STATUS_ENUM(status) == FT_OK || throw(FT_STATUS_ENUM(status))
  return
end

function status(handle::FT_HANDLE)
  flags = Ref{DWORD}()
  status = ccall(cfunc[:FT_GetModemStatus], cdecl, FT_STATUS, 
                 (FT_HANDLE, Ref{DWORD}),
                  handle,    flags)
  FT_STATUS_ENUM(status) == FT_OK || throw(FT_STATUS_ENUM(status))
  modemstatus = flags[] & 0xFF
  linestatus = (flags[] >> 8) & 0xFF
  mflaglist = Dict{String, Bool}()
  lflaglist = Dict{String, Bool}()
  mflaglist["CTS"] = modemstatus & 0x10
  mflaglist["DSR"] = modemstatus & 0x20
  mflaglist["RI"]  = modemstatus & 0x40
  mflaglist["DCD"] = modemstatus & 0x80
  lflaglist["OE"] = linestatus & 0x02
  lflaglist["PE"] = linestatus & 0x04
  lflaglist["FE"] = linestatus & 0x08
  lflaglist["BI"] = linestatus & 0x10
  mflaglist, lflaglist
end

function Base.nb_available(handle::FT_HANDLE)
  nbrx = Ref{DWORD}()
  status = ccall(cfunc[:FT_GetQueueStatus], cdecl, FT_STATUS, 
                 (FT_HANDLE, Ref{DWORD}),
                  handle,    nbrx)
  FT_STATUS_ENUM(status) == FT_OK || throw(FT_STATUS_ENUM(status))
  nbrx[]
end

Base.eof(handle::FT_HANDLE) = (nb_available(handle) == 0)

function Base.readavailable(handle::FT_HANDLE)
  b = Vector{UInt8}(nb_available(handle))
  readbytes!(handle, b)
  b
end

function Base.open(str::AbstractString, openby::FTOpenBy)
  flagsarg = DWORD(openby)
  handle = FT_HANDLE()
  status = ccall(cfunc[:FT_OpenEx], cdecl, FT_STATUS, 
                 (Cstring, DWORD,    Ref{FT_HANDLE}),
                  str,     flagsarg, handle)
  if FT_STATUS_ENUM(status) != FT_OK
    handle.p = C_NULL
    throw(FT_STATUS_ENUM(status))
  end
  handle
end

function Base.flush(handle::FT_HANDLE)
  flagsarg = DWORD(FT_PURGE_RX | FT_PURGE_TX)
  status = ccall(cfunc[:FT_Purge], cdecl, FT_STATUS, 
                 (FT_HANDLE, DWORD),
                  handle,    flagsarg)
  FT_STATUS_ENUM(status) == FT_OK || throw(FT_STATUS_ENUM(status))
  return
end

function Base.isopen(handle::FT_HANDLE)
  open = true
  if handle.p == C_NULL
    open = false
  else
    try
      status(handle)
    catch ex
      if ex == FT_INVALID_HANDLE
        open = false
      else
        rethrow(ex)
      end
    end
  end
  open
end

end # module FTD2XX