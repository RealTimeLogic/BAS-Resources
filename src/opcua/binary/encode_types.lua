return {
  HeaderType = {
    Message = "MSG",
    Open = "OPN",
    Close = "CLO",
    Hello = "HEL",
    ReverseHello = "RHE",
    Acknowledge = "ACK",
    Error = "ERR"
  },

  ChunkType = {
    Final = "F", -- final message chunk
    Intermediate = "C", -- intermediate message chunk
    Abort = "A" -- abort multichunk message
  }
}
