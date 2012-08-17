%%%-------------------------------------------------------------------
%% @copyright Geoff Cant
%% @author Geoff Cant <nem@erlang.geek.nz>
%% @version {@vsn}, {@date} {@time}
%% @doc 
%% @end
%%%-------------------------------------------------------------------
-module(gpt).

%% API
-export([]).

-compile(export_all).

%%====================================================================
%% API
%%====================================================================

describe(FName, mbr) ->
    describe(FName, 512, fun mbr/1);
describe(FName, gpt) ->
    describe(FName, 512, fun gpt/1);
describe(FName, gpt_part) ->
    describe(FName, 128, fun gpt_partition/1);
describe(_,Type) ->
    erlang:error({not_implemented, Type}).

describe(File, BlockSize, Function) ->
    Blocks = blocks(read_file(File), BlockSize),
    NumBlocks = lists:zip(lists:seq(0, length(Blocks) - 1), Blocks),
    [{BN, catch Function(B)} || {BN, B} <- NumBlocks].


hex_diff(File1, File2) when is_list(File1), is_list(File2) ->
    Bin1 = read_file(File1),
    Bin2 = read_file(File2),
    hex_diff(Bin1, Bin2, 0).

hex_diff(<<>>,_, N) -> [];
hex_diff(<< A, Rest1/binary>>, << A, Rest2/binary>>, N) -> [ {N, A} | hex_diff(Rest1, Rest2, N+1) ];
hex_diff(<< A, Rest1/binary>>, << B, Rest2/binary>>, N) -> [ {N, {A, B}} | hex_diff(Rest1, Rest2, N+1) ].
    

read_file(FName) ->
    {ok, Bin} = file:read_file(FName),
    Bin.

blocks(Bin) ->
    blocks(Bin, 512).

blocks(Bin, BlockSize) ->
    [Block || <<Block:BlockSize/binary>> <= Bin].

non_zero_blocks(Bin, BlockSize) ->
    [Block || <<Block:BlockSize/binary>> <= Bin, Block =/= << 0:(BlockSize*8) >>].

mbr(<< _Code:440/binary,
     DiskSig:4/binary,
     0, 0,
     PartTable:64/binary,
     (16#aa55):16/little, _Rest/binary>>) ->
    {mbr, DiskSig,
     [ mbr_partition(Part)
       || <<Part:16/binary>> <= PartTable ] };
mbr(_) ->
    not_mbr.

mbr_partition(<< Status,
               FirstBlockCHS:3/binary,
               Type,
               LastBlockCHS:3/binary,
               FirstBlockLBA:32/little,
               BlockLength:32/little>>) ->
    {partition, case Status of
                    16#80 -> bootable;
                    0 -> non_bootable;
                    _ -> invalid
                end,
     Type,
     {FirstBlockLBA,
      BlockLength}}.

gpt(<<"EFI PART",
     Revision:32/little,
     HeaderSize:32/little,
     HeaderCRC:32/little,
     (0):32/little,
     MyLBA:64/little,
     AlternateLBA:64/little,
     FirstUsableLBA:64/little,
     LastUsableLBA:64/little,
     DiskGUID:16/binary,
     PartitionEntryLBA:64/little,
     NumberOfPartitions:32/little,
     SizeOfPartitionEntry:32/little,
     PartitionEntryArrayCRC:32/little,
     _Reserved:(512-92)/binary,
     _Rest/binary>> = Block) ->
    <<Header:HeaderSize/binary, _/binary>> = Block,
    {gpt, [{revision, Revision},
           {header, HeaderSize, HeaderCRC,
            erlang:crc32(Header) bxor 16#FFFFFFFF},
           {lbas, [{my, MyLBA},
                   {alternate, AlternateLBA},
                   {first, FirstUsableLBA},
                   {last, LastUsableLBA},
                   {partition_entries, PartitionEntryLBA}]},
           {guid, DiskGUID},
           {partition_entries,
            SizeOfPartitionEntry,
            NumberOfPartitions,
            PartitionEntryArrayCRC}]}.

gpt_partition(<< 0:(128*8) >>) ->
    empty_gpt_part;
gpt_partition(<<TypeGUID:16/binary,
               PartGUID:16/binary,
               StartLBA:64/little,
               EndLBA:64/little,
               Attributes:8/binary,
               Name:72/binary>>) ->
    Size = (EndLBA-StartLBA) * 512,
    {gpt_part, gpt_part_name(Name),
     [{start, StartLBA}, {'end', EndLBA},
      {count, EndLBA - StartLBA + 1},
      {size, [{Size / 1024 / 1024 / 1024, gig},
              {Size / 1024 / 1024, meg},
              {Size / 1024, k},
              {Size,b}]},
      {guids, [{type, gpt_part_type(TypeGUID)},
               {part, PartGUID}]},
      {attributes, Attributes}]}.

%%====================================================================
%% Internal functions
%%====================================================================

gpt_part_name(Name) ->
    UniList = unicode:characters_to_list(Name, {utf16,little}),
    lists:reverse(lists:dropwhile(fun (C) -> C=:=0 end, lists:reverse(UniList))).

gpt_part_types() ->
    [{hfs, <<0,83,70,72,0,0,170,17,170,17,0,48,101,67,236,172>>},
     {efi, <<40,115,42,193,31,248,210,17,186,75,0,160,201,62,201,59>>},
     {ms_basic, <<16#EB,16#D0,16#A0,16#A2,16#B9,16#E5,16#44,16#33,16#87,16#C0,16#68,16#B6,16#B7,16#26,16#99,16#C7>>}
    ].

gpt_part_type(UUID) ->
    case lists:keysearch(UUID, 2, gpt_part_types()) of
        {value, {Type, _}} -> {Type, UUID};
        false -> {unknown, UUID}
    end.

cmd(Disk, Idx, GptData) ->
    {gpt_part, _Name, Data} = proplists:get_value(Idx -1, GptData),
    StartLBA = proplists:get_value(start, Data), true = is_integer(StartLBA),
    Count = proplists:get_value(count, Data), true = is_integer(Count),
    Guids = proplists:get_value(guids, Data, []),
    {Type, UUID} = proplists:get_value(type, Guids),
    lists:flatten(io_lib:format("gpt add -i ~p -b ~p -s ~p -t ~s ~s",
                                [Idx, StartLBA, Count, atom_to_list(Type), Disk])).
