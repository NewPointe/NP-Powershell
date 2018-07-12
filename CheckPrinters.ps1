
# Printer Connection Timeout
$TIMEOUT = 2000;

$READ_BUFFER_SIZE = 1024;
$READ_ENCODING = New-Object System.Text.AsciiEncoding;
$BYTE_START_OF_TEXT = [System.Byte] 2;
$BYTE_END_OF_TEXT = [System.Byte] 3;

<#
.SYNOPSIS
Gets the targeted printer's settings in xml format.
.DESCRIPTION
The Get-PrinterSettingsXML function retrieves the printer's xml configuration and returns it as a configuration object. An example of this configuration can be seen in ExamplePrinterSettings.xml.
.PARAMETER printerIp
The ip of the printer.
.PARAMETER port
The port to connect to (defaults to 9100).
.EXAMPLE
Get the name of a printer.
(Get-PrinterSettingsXML 0.0.0.0)["ZEBRA-ELTRON-PERSONALITY"]["SAVED-SETTINGS"]["NAME"]
.NOTES
Some printers return invalid xml and this function fails. We can't really do anything about that.
#>
Function Get-PrinterSettingsXML([string] $printerIp, [int] $port = 9100) {
    [xml](Send-PrinterCommand "^XA^HZS^XZ" $printerIp $port "</ZEBRA-ELTRON-PERSONALITY>");
}

<#
.SYNOPSIS
Sends a command to a printer and reads it's response (if any).
.DESCRIPTION
The Send-PrinterCommand function sends a command to the printer and then attempts to read it's response.
.PARAMETER command
The command to send.
.PARAMETER printerIp
The ip of the printer.
.PARAMETER port
The port to connect to (defaults to 9100).
.PARAMETER endText
An optional string to listen for to indicate the end of a response.
.EXAMPLE
Get the diagnostics printout of a printer.
Send-PrinterCommand "~HD" 0.0.0.0
.NOTES
Since some commands give different responses, or none at all, there's no guarentee that a command has (or hasn't) run successfuly.
#>
Function Send-PrinterCommand([string] $command, [string] $printerIp, [int] $port = 9100, [string] $endText = "") {

    # Create a new tcp client and connect the printer
    $client = New-Object System.Net.Sockets.TcpClient;
    if ( -Not $client.ConnectAsync($printerIp, $port).Wait($TIMEOUT))
    {
        Throw "Failed to connect to ${printerIp}:$port";
    }

    # Get a data stream for the socket
    $stream = $client.GetStream();

    # Create a new Writer and write our command to the stream
    $writer = New-Object System.IO.StreamWriter($stream);
    $writer.WriteLine($command);
    $writer.Flush();

    # Response string
    $response = "";

    # Timeout counter
    $timeoutCounter = 0;

    # While the timeout's not expired
    while ($timeoutCounter -lt $TIMEOUT) {

        # Check if there's data available
        if($stream.DataAvailable) {

            # We got some data so reset the timeout
            $timeoutCounter = 0;

            # Create the Read Buffer
            $buffer = New-Object System.Byte[] $READ_BUFFER_SIZE;

            # Fill the buffer
            $readSize = $stream.Read($buffer, 0, $READ_BUFFER_SIZE);

            # Calculate beginning/ending of string
            $beginIndex = 0;
            $endIndex = $readSize;
            $foundEnd = $false;
            for ($i = 0; $i -lt $readSize; $i++) {
                $byte = $buffer[$i];
                if($byte -eq $BYTE_START_OF_TEXT) {
                    $beginIndex = $i + 1;
                }
                if($byte -eq $BYTE_END_OF_TEXT) {
                    $foundEnd = $true;
                    $endIndex = $i;
                }
            }

            # Decode Bytes and add to response
            if($endIndex -gt $beginIndex) {
                $response += $READ_ENCODING.GetString($buffer, $beginIndex, $endIndex - $beginIndex);
            }
            else {
                $response += $READ_ENCODING.GetString($buffer, 0, $readSize);
            }

            # Check for custom end text since some commands don't use an END-OF-TEXT character
            if($endText -ne "" -and $response.Contains($endText)) { $foundEnd = $true; }

            # If we got the end, stop reading
            if($foundEnd) { break; }
        }
        else {

            # Increment the timeout and wait a bit for more data
            $timeoutCounter += 50;
            start-sleep -Milliseconds 50;
        }
    }

    # If we timed out, throw an error
    if( -Not $timeoutCounter -lt $TIMEOUT) { Throw "Read timed out for ${printerIp}:$port"; }

    # Close everything
    $writer.Close()
    $stream.Close()

    # Return
    $response
}

# All of our check-in printers
$printers = @(
    # Dover
    @{ Ip="10.1.27.1"; },
    @{ Ip="10.1.27.2"; },
    @{ Ip="10.1.27.3"; },
    @{ Ip="10.1.27.4"; },
    @{ Ip="10.1.27.5"; },
    @{ Ip="10.1.27.6"; },
    @{ Ip="10.1.27.7"; },
    @{ Ip="10.1.27.8"; },
    @{ Ip="10.1.27.9"; },
    @{ Ip="10.1.27.10"; },
    @{ Ip="10.1.27.11"; },
    @{ Ip="10.1.27.12"; },
    @{ Ip="10.1.27.13"; },
    @{ Ip="10.1.27.36"; },
    @{ Ip="10.1.27.37"; },
    @{ Ip="10.1.27.39"; },
    @{ Ip="10.1.27.127"; },
    # Millersburg
    @{ Ip="10.2.27.11"; },
    @{ Ip="10.2.27.12"; },
    @{ Ip="10.2.27.13"; },
    @{ Ip="10.2.27.14"; },
    @{ Ip="10.2.27.106"; },
    # Canton
    @{ Ip="10.3.27.11"; },
    @{ Ip="10.3.27.12"; },
    @{ Ip="10.3.27.13"; },
    @{ Ip="10.3.27.14"; },
    @{ Ip="10.3.27.15"; },
    @{ Ip="10.3.27.27"; }
    # Coshocton
    # -
    # Wooster
    # -
)

# Get the current config for each one
$i = 0
foreach ($printer in $printers) {
    Write-Progress -Activity "Checking Printers" -Status "Checking $($printer.Ip)" -PercentComplete ($i++ / $printers.count * 100)
    try {
        $settings = (Get-PrinterSettingsXML $printer.Ip)["ZEBRA-ELTRON-PERSONALITY"]["SAVED-SETTINGS"]
        $printer.Name = $settings["NAME"].InnerText
        $printer.CurrentMode = $settings["PRINT-MODE"]["MODE"]["CURRENT"].InnerText
        $printer.SavedMode = $settings["PRINT-MODE"]["MODE"]["STORED"].InnerText
    }
    catch {
        Write-Warning "$_"
        $printer.Name = "ERROR"
        $printer.CurrentMode = $printer.SavedMode = "-"
    }
}
$printers.ForEach({[PSCustomObject]$_}) | Format-Table Ip, Name, CurrentMode, SavedMode -AutoSize
