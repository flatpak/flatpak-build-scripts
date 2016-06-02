#!/usr/bin/python
# Copyright (C) 2016 Endless Mobile, Inc.
# Author: Tristan Van Berkom <tristan@codethink.co.uk>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library. If not, see <http://www.gnu.org/licenses/>.


#
# This is not a bot, only a very simple script to send a message to an
# IRC channel and then quit.
#
import sys
import argparse
from twisted.internet import defer, endpoints, protocol, reactor, task
from twisted.python import log
from twisted.words.protocols import irc

GREEN = 3
RED   = 4
def irc_color(code, S):
    return "\x03%d%s\x03" % (code, S)

class FlatpakIRCProtocol(irc.IRCClient):

    def __init__(self):
        global args
        self.nickname = args.nick
        self.deferred = defer.Deferred()

    def connectionLost(self, reason):
        # TODO: Check if we lost the connection because we quit,
        # if it's another error we should ensure an error status is returned.
        reactor.stop()

    def signedOn(self):
        global args
        for channel in self.factory.channels:
            if args.join:
                self.join(channel)

            if args.type == 'success':
                self.msg(channel, irc_color (GREEN, args.message))
            elif args.type == 'fail':
                self.msg(channel, irc_color (RED, args.message)) 
            else:
                self.msg(channel, args.message)

        self.quit()

    def _showError(self, failure):
        return failure.getErrorMessage()


class FlatpakIRCFactory(protocol.ReconnectingClientFactory):
    def __init__(self):
        global args
        self.protocol = FlatpakIRCProtocol
        self.channels = [ args.channel ]

def main(reactor, description):
    endpoint = endpoints.clientFromString(reactor, description)
    factory = FlatpakIRCFactory()
    d = endpoint.connect(factory)
    d.addCallback(lambda protocol: protocol.deferred)
    return d

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument ('-s', dest='server', required=True,
                         help="The IRC server to connect to")
    parser.add_argument ('-p', dest='port', default='6667',
                         help="The port to connect to (default: 6667)")
    parser.add_argument ('-c', dest='channel', required=True,
                         help="The channel to announce in")
    parser.add_argument ('-n', dest='nick', required=True,
                         help="The nickname to use")
    parser.add_argument ('-t', dest='type', default='regular', choices=['success', 'fail', 'regular'],
                         help="Type of message to send")
    parser.add_argument ('--nojoin', dest='join', action='store_false',
                         help="Send the message to channel without joining")
    parser.add_argument ('message')
    args = parser.parse_args()

    connect_str = 'tcp:' + args.server + ':' + args.port
    log.startLogging(sys.stderr)
    task.react(main, [ connect_str ])
