/**
 * Copyright (C) 2009-2010 Michael 'Mickey' Lauer <mlauer@vanille-media.de>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.

 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 */

using GLib;

namespace SyncTime {
    const string MODULE_NAME = "fsotdl.sync_time";
    const string TIMEZONE_FILE_DEFAULT = "/etc/timezone";
    const string ZONEINFO_DIR_DEFAULT = "/usr/share/zoneinfo";
}

class SyncTime.Service : FsoFramework.AbstractObject
{
    FsoFramework.Subsystem subsystem;
    private Gee.HashMap<string,FsoTime.Source> sources;
    private string timezone_file;
    private string zoneinfo_dir;

    public Service( FsoFramework.Subsystem subsystem )
    {
        sources = new Gee.HashMap<string,FsoTime.Source>();
        var sourcenames = config.stringListValue( MODULE_NAME, "sources", {} );
        foreach ( var source in sourcenames )
        {
            addSource( source );
        }
        timezone_file = config.stringValue( MODULE_NAME, "timezone_file", TIMEZONE_FILE_DEFAULT );
        zoneinfo_dir = config.stringValue( MODULE_NAME, "zoneinfo_dir", ZONEINFO_DIR_DEFAULT );
        logger.info( @"Ready. Configured for $(sources.size) sources" );
    }

    public void addSource( string name )
    {
        var typename = "unknown";

        switch ( name )
        {
            case "ntp":
                typename = "SourceNtp";
                break;
            case "gps":
                typename = "SourceGps";
                break;
            case "gsm":
                typename = "SourceGsm";
                break;
            default:
                logger.warning( @"Unknown source $name - Ignoring" );
                return;
        }
        var sourceclass = Type.from_name( typename );
        if ( sourceclass == Type.INVALID  )
        {
            logger.warning( @"Can't find source $name (type=$typename) - plugin loaded?" );
            return;
        }
        sources[name] = (FsoTime.Source) Object.new( sourceclass );
        logger.info( @"Added source $name ($typename)" );
        sources[name].reportTime.connect( onTimeReport );
        sources[name].reportZone.connect( onZoneReport );
        sources[name].reportLocation.connect( onLocationReport );
    }

    public override string repr()
    {
        return @"<$(sources.size)>";
    }

    public void onTimeReport( int since_epoch, FsoTime.Source source )
    {
        time_t now = time_t();
        int offset = since_epoch-(int)now;

        assert( logger.debug( "%s reports %u, we think %u, offset = %d".printf( ((FsoFramework.AbstractObject)source).classname, (uint)since_epoch, (uint)now, (int)offset ) ) );

        var tv = Posix.timeval() { tv_sec = (time_t)offset };
        var res = Linux.adjtime( tv );

        if ( res != 0 )
        {
            logger.warning( @"Can't adjtime(2): $(strerror(errno))" );
        }
    }

    public void onZoneReport( string zone, FsoTime.Source source )
    {
        assert( logger.debug( "%s reports time zone '%s'".printf( ((FsoFramework.AbstractObject)source).classname, zone ) ) );

        var newzone = GLib.Path.build_filename( zoneinfo_dir, zone );
        if ( !FsoFramework.FileHandling.isPresent( newzone ) )
        {
            logger.warning( @"Timezone file $newzone not present; ignoring zone report" );
            return;
        }
        assert( logger.debug( @"Removing $timezone_file and symlinking to $newzone" ) );

        var res = GLib.FileUtils.remove( timezone_file );
        if ( res != 0 )
        {
            logger.warning( @"Can't remove $(timezone_file): $(strerror(errno))" );
        }
        res = GLib.FileUtils.symlink( newzone, timezone_file );
        if ( res != 0 )
        {
            logger.warning( @"Can't symlink $timezone_file -> $newzone: $(strerror(errno))" );
        }
        else
        {
            /* found in mktime.c:
             * "POSIX.1 8.1.1 requires that whenever mktime() is called, the
             * time zone names contained in the external variable `tzname' shall
             * be set as if the tzset() function had been called."
             *
             * Hence, timezones will be reread, this we should be ok. */
            var t = GLib.Time();
            t.mktime();
        }
    }

    public void onLocationReport( double lat, double lon, int height, FsoTime.Source source )
    {
        assert( logger.debug( "%s reports position %.2f %.2f - %d".printf( ((FsoFramework.AbstractObject)source).classname, lat, lon, height ) ) );
    }
}

SyncTime.Service service;

/**
 * This function gets called on plugin initialization time.
 * @return the name of your plugin here
 * @note that it needs to be a name in the format <subsystem>.<plugin>
 * else your module will be unloaded immediately.
 **/
public static string fso_factory_function( FsoFramework.Subsystem subsystem ) throws Error
{
    service = new SyncTime.Service( subsystem );
    return SyncTime.MODULE_NAME;
}

[ModuleInit]
public static void fso_register_function( TypeModule module )
{
    FsoFramework.theLogger.debug( "fsotdl.sync_time fso_register_function" );
}

/**
 * This function gets called on plugin load time.
 * @return false, if the plugin operating conditions are present.
 * @note Some versions of glib contain a bug that leads to a SIGSEGV
 * in g_module_open, if you return true here.
 **/
/*public static bool g_module_check_init( void* m )
{
    var ok = FsoFramework.FileHandling.isPresent( Kernel26.SYS_CLASS_LEDS );
    return (!ok);
}
*/